/*
 * Copyright (c) 2010-2022 Belledonne Communications SARL.
 *
 * This file is part of Liblinphone
 * (see https://gitlab.linphone.org/BC/public/liblinphone).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#include <algorithm>
#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "bctoolbox/defs.h"
#include "belle_sip_tester_utils.h"
#include "liblinphone_tester.h"
#include "linphone/api/c-account-cbs.h"
#include "linphone/api/c-account-params.h"
#include "linphone/api/c-account.h"
#include "linphone/api/c-address.h"
#include "linphone/core.h"
#include "sal/sal.h"
#include "tester_utils.h"

// linphone_account_send_ping() against an in-process SIP server, so no external test server is needed.

namespace {

constexpr int kNoReply = 0;
constexpr int kCloseConnection = -1;
constexpr const char *kIdentity = "sip:bob@sip.example.org";

// Accepts any REGISTER and answers each OPTIONS as configured. It runs on its own thread, so whatever the test reads
// from it is atomic or locked.
class PingServer {
public:
	PingServer() : mAgent("sip.example.org", "tcp") {
		mAgent.setRequestHandler([this](bellesip::QuickSipAgent &agent, const belle_sip_request_event_t *event) {
			return onRequest(agent, event);
		});
	}

	std::string getUri() {
		return mAgent.getListeningUriAsString();
	}

	// One reply per OPTIONS in arrival order, the last one repeating. kNoReply leaves it unanswered and
	// kCloseConnection closes the connection instead of answering.
	void setOptionsReplies(std::vector<int> codes, int delayMs = 0) {
		std::lock_guard<std::mutex> lock(mMutex);
		mReplies = std::move(codes);
		mDelayMs = delayMs;
	}

	int getOptionsCount() const {
		return mOptionsCount;
	}

	std::string getLastOptionsFrom() {
		std::lock_guard<std::mutex> lock(mMutex);
		return mLastOptionsFrom;
	}

private:
	bool onRequest(bellesip::QuickSipAgent &agent, const belle_sip_request_event_t *event) {
		belle_sip_request_t *request = belle_sip_request_event_get_request(event);
		const std::string method = belle_sip_request_get_method(request);
		if (method == "REGISTER") {
			reply(agent, request, 200, 0, true);
		} else if (method == "OPTIONS") {
			int code;
			int delayMs;
			{
				std::lock_guard<std::mutex> lock(mMutex);
				const size_t index = static_cast<size_t>(mOptionsCount);
				code = mReplies.empty() ? 200 : mReplies[std::min(index, mReplies.size() - 1)];
				delayMs = mDelayMs;
				auto from = belle_sip_message_get_header_by_type(request, belle_sip_header_from_t);
				auto uri = belle_sip_header_address_get_uri(BELLE_SIP_HEADER_ADDRESS(from));
				const char *user = belle_sip_uri_get_user(uri);
				mLastOptionsFrom = std::string(user ? user : "") + "@" + belle_sip_uri_get_host(uri);
			}
			mOptionsCount++;
			if (code == kCloseConnection) {
				// Outside the request callback, since it closes the channel the request came in on.
				agent.doLater(
				    "close connection",
				    [&agent]() {
					    belle_sip_listening_point_clean_channels(
					        belle_sip_provider_get_listening_point(agent.getProv(), "tcp"));
				    },
				    0);
			} else if (code != kNoReply) {
				reply(agent, request, code, delayMs, false);
			}
		}
		return false;
	}

	static void
	reply(bellesip::QuickSipAgent &agent, belle_sip_request_t *request, int code, int delayMs, bool registration) {
		belle_sip_server_transaction_t *transaction =
		    belle_sip_provider_create_server_transaction(agent.getProv(), request);
		belle_sip_response_t *response = belle_sip_response_create_from_request(request, code);
		if (registration) {
			// Echo the binding back so the account sees its own contact and expiry.
			auto contact = belle_sip_message_get_header_by_type(request, belle_sip_header_contact_t);
			if (contact)
				belle_sip_message_add_header(BELLE_SIP_MESSAGE(response),
				                             BELLE_SIP_HEADER(belle_sip_object_clone(BELLE_SIP_OBJECT(contact))));
			auto expires = belle_sip_message_get_header_by_type(request, belle_sip_header_expires_t);
			if (expires)
				belle_sip_message_add_header(BELLE_SIP_MESSAGE(response),
				                             BELLE_SIP_HEADER(belle_sip_object_clone(BELLE_SIP_OBJECT(expires))));
		}
		if (delayMs == 0) {
			belle_sip_server_transaction_send_response(transaction, response);
			return;
		}
		belle_sip_object_ref(transaction);
		belle_sip_object_ref(response);
		agent.doLater(
		    "delayed reply",
		    [transaction, response]() {
			    belle_sip_server_transaction_send_response(transaction, response);
			    belle_sip_object_unref(response);
			    belle_sip_object_unref(transaction);
		    },
		    delayMs);
	}

	std::mutex mMutex;
	std::vector<int> mReplies;
	int mDelayMs = 0;
	std::string mLastOptionsFrom;
	std::atomic<int> mOptionsCount{0};
	// Last, so its thread stops before the state the request handler uses is destroyed.
	bellesip::QuickSipAgent mAgent;
};

struct PingResults {
	int count = 0;
	int code = -1;
	LinphoneReason reason = LinphoneReasonUnknown;
};

void onPingResult(LinphoneAccount *account, const LinphoneErrorInfo *errorInfo) {
	auto results =
	    static_cast<PingResults *>(linphone_account_cbs_get_user_data(linphone_account_get_current_callbacks(account)));
	results->count++;
	results->code = linphone_error_info_get_protocol_code(errorInfo);
	results->reason = linphone_error_info_get_reason(errorInfo);
}

// A core with one account on the PingServer. The test keeps no reference to the account, so removing it from the core
// can destroy it while its ping is still in flight.
class PingFixture {
public:
	explicit PingFixture(bool registerEnabled = true, LinphonePrivacyMask privacy = LinphonePrivacyDefault) {
		mManager = linphone_core_manager_new("empty_rc");
		LinphoneCore *lc = getCore();
		// T1 = 50 ms brings the 32 s transaction timeout (64 * T1) down to 3.2 s.
		belle_sip_timer_config_t timers = {50, 4000, 0, 5000};
		belle_sip_stack_set_timer_config(static_cast<belle_sip_stack_t *>(linphone_core_get_sal(lc)->getStackImpl()),
		                                 &timers);

		LinphoneAccountParams *params = linphone_account_params_new(lc, TRUE);
		LinphoneAddress *server = linphone_address_new(mServer.getUri().c_str());
		LinphoneAddress *identity = linphone_address_new(kIdentity);
		linphone_account_params_set_server_address(params, server);
		linphone_account_params_set_identity_address(params, identity);
		linphone_account_params_enable_register(params, registerEnabled);
		linphone_account_params_set_privacy(params, privacy);
		LinphoneAccount *account = linphone_account_new(lc, params);
		linphone_address_unref(server);
		linphone_address_unref(identity);
		linphone_account_params_unref(params);

		LinphoneAccountCbs *cbs = linphone_factory_create_account_cbs(linphone_factory_get());
		linphone_account_cbs_set_ping_result(cbs, onPingResult);
		linphone_account_cbs_set_user_data(cbs, &mResults);
		linphone_account_add_callbacks(account, cbs);
		linphone_account_cbs_unref(cbs);

		linphone_core_add_account(lc, account);
		linphone_core_set_default_account(lc, account);
		linphone_account_unref(account);
	}

	~PingFixture() {
		// Before the server goes away, so the unREGISTER on shutdown still gets an answer.
		linphone_core_manager_destroy(mManager);
	}

	LinphoneCore *getCore() const {
		return mManager->lc;
	}

	LinphoneAccount *getAccount() const {
		return linphone_core_get_default_account(getCore());
	}

	LinphoneCoreManager *getManager() const {
		return mManager;
	}

	PingServer &getServer() {
		return mServer;
	}

	const PingResults &getResults() const {
		return mResults;
	}

	bool waitRegistered() {
		return BC_ASSERT_TRUE(
		    wait_for_until(getCore(), NULL, &mManager->stat.number_of_LinphoneRegistrationOk, 1, 5000));
	}

	bool waitForResult(int count, int timeoutMs = 5000) {
		return wait_for_until(getCore(), NULL, &mResults.count, count, timeoutMs);
	}

	bool waitForOptions(int count, int timeoutMs = 5000) {
		for (int elapsedMs = 0; elapsedMs < timeoutMs; elapsedMs += 20) {
			if (mServer.getOptionsCount() >= count) return true;
			wait_for_until(getCore(), NULL, NULL, 0, 20);
		}
		return mServer.getOptionsCount() >= count;
	}

	void iterate(int durationMs) {
		wait_for_until(getCore(), NULL, NULL, 0, durationMs);
	}

private:
	PingServer mServer;
	PingResults mResults;
	LinphoneCoreManager *mManager = nullptr;
};

} // namespace

// The 2xx path once came out as code 0 (no response), so pin the status code and reason.
static void ping_answered_with_200(void) {
	PingFixture fixture;
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	BC_ASSERT_EQUAL(fixture.getResults().code, 200, int, "%d");
	BC_ASSERT_EQUAL(fixture.getResults().reason, LinphoneReasonNone, int, "%d");
	BC_ASSERT_EQUAL(fixture.getServer().getOptionsCount(), 1, int, "%d");
}

// Registration isn't required: with no connection to the proxy yet, the ping opens one.
static void ping_sent_when_not_registered(void) {
	PingFixture fixture(false);

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	BC_ASSERT_EQUAL(fixture.getResults().code, 200, int, "%d");
	BC_ASSERT_EQUAL(fixture.getServer().getOptionsCount(), 1, int, "%d");
}

// Any response means the connection is up, so an error status is reported as is.
static void ping_reports_error_response(void) {
	PingFixture fixture;
	fixture.getServer().setOptionsReplies({404, 500});
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	BC_ASSERT_EQUAL(fixture.getResults().code, 404, int, "%d");

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(2));
	BC_ASSERT_EQUAL(fixture.getResults().code, 500, int, "%d");
}

static void ping_times_out_when_unanswered(void) {
	PingFixture fixture;
	fixture.getServer().setOptionsReplies({kNoReply});
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1, 6000));
	BC_ASSERT_EQUAL(fixture.getResults().code, 0, int, "%d");
	BC_ASSERT_EQUAL(fixture.getResults().reason, LinphoneReasonNotAnswered, int, "%d");
}

static void second_ping_replaces_first(void) {
	PingFixture fixture;
	// Both answers arrive after both pings are out; only the second ping's 200 may be reported.
	fixture.getServer().setOptionsReplies({404, 200}, 300);
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	fixture.iterate(500);
	BC_ASSERT_EQUAL(fixture.getResults().count, 1, int, "%d");
	BC_ASSERT_EQUAL(fixture.getResults().code, 200, int, "%d");
	BC_ASSERT_EQUAL(fixture.getServer().getOptionsCount(), 2, int, "%d");
}

// With keepAccount, the account outlives its removal with its callbacks attached, so only releasing the ping op on
// removal keeps the timeout from being reported. Without it, the account itself is destroyed under the ping.
static void ping_in_flight_when_account_removed_base(bool keepAccount) {
	PingFixture fixture;
	fixture.getServer().setOptionsReplies({kNoReply});
	if (!fixture.waitRegistered()) return;

	LinphoneAccount *account = fixture.getAccount();
	if (keepAccount) linphone_account_ref(account);
	BC_ASSERT_EQUAL(linphone_account_send_ping(account), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForOptions(1));
	linphone_core_remove_account(fixture.getCore(), account);
	// The account is released once its unREGISTER is answered, well before the ping's 3.2 s timeout.
	BC_ASSERT_TRUE(wait_for_until(fixture.getCore(), NULL,
	                              &fixture.getManager()->stat.number_of_LinphoneRegistrationCleared, 1, 5000));
	fixture.iterate(4000);
	BC_ASSERT_EQUAL(fixture.getResults().count, 0, int, "%d");
	if (keepAccount) linphone_account_unref(account);
}

static void ping_in_flight_when_account_removed(void) {
	ping_in_flight_when_account_removed_base(true);
}

static void ping_in_flight_when_account_destroyed(void) {
	ping_in_flight_when_account_removed_base(false);
}

static void ping_in_flight_when_core_stops(void) {
	PingFixture fixture;
	fixture.getServer().setOptionsReplies({kNoReply});
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForOptions(1));
	linphone_core_stop(fixture.getCore());
	BC_ASSERT_TRUE(
	    wait_for_until(fixture.getCore(), NULL, &fixture.getManager()->stat.number_of_LinphoneGlobalOff, 1, 5000));
	BC_ASSERT_EQUAL(fixture.getResults().count, 0, int, "%d");
}

static void ping_not_sent_after_core_stops(void) {
	PingFixture fixture;
	if (!fixture.waitRegistered()) return;

	LinphoneAccount *account = linphone_account_ref(fixture.getAccount());
	linphone_core_stop(fixture.getCore());
	BC_ASSERT_TRUE(
	    wait_for_until(fixture.getCore(), NULL, &fixture.getManager()->stat.number_of_LinphoneGlobalOff, 1, 5000));
	BC_ASSERT_EQUAL(linphone_account_send_ping(account), -1, int, "%d");
	linphone_account_unref(account);
}

// The SIP proxy drops requests whose From isn't the account identity, so privacy must not anonymize the ping.
static void ping_keeps_identity_with_privacy(void) {
	PingFixture fixture(true, LinphonePrivacyUser | LinphonePrivacyId);
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	BC_ASSERT_EQUAL(fixture.getResults().code, 200, int, "%d");
	const std::string from = fixture.getServer().getLastOptionsFrom();
	BC_ASSERT_STRING_EQUAL(from.c_str(), "bob@sip.example.org");
}

static void ping_reports_io_error_when_connection_closes(void) {
	PingFixture fixture;
	fixture.getServer().setOptionsReplies({kCloseConnection});
	if (!fixture.waitRegistered()) return;

	BC_ASSERT_EQUAL(linphone_account_send_ping(fixture.getAccount()), 0, int, "%d");
	BC_ASSERT_TRUE(fixture.waitForResult(1));
	BC_ASSERT_EQUAL(fixture.getResults().code, 0, int, "%d");
	BC_ASSERT_EQUAL(fixture.getResults().reason, LinphoneReasonIOError, int, "%d");
}

static test_t account_ping_tests[] = {
    TEST_NO_TAG("Ping answered with 200", ping_answered_with_200),
    TEST_NO_TAG("Ping sent when not registered", ping_sent_when_not_registered),
    TEST_NO_TAG("Ping reports an error response", ping_reports_error_response),
    TEST_NO_TAG("Ping times out when unanswered", ping_times_out_when_unanswered),
    TEST_NO_TAG("Second ping replaces the first", second_ping_replaces_first),
    TEST_NO_TAG("Ping in flight when the account is removed", ping_in_flight_when_account_removed),
    TEST_NO_TAG("Ping in flight when the account is destroyed", ping_in_flight_when_account_destroyed),
    TEST_NO_TAG("Ping in flight when the core stops", ping_in_flight_when_core_stops),
    TEST_NO_TAG("Ping not sent after the core stops", ping_not_sent_after_core_stops),
    TEST_NO_TAG("Ping keeps the identity with privacy on", ping_keeps_identity_with_privacy),
    TEST_NO_TAG("Ping reports an IO error when the connection closes", ping_reports_io_error_when_connection_closes),
};

test_suite_t account_ping_test_suite = {"Account ping",
                                        NULL,
                                        NULL,
                                        liblinphone_tester_before_each,
                                        liblinphone_tester_after_each,
                                        sizeof(account_ping_tests) / sizeof(account_ping_tests[0]),
                                        account_ping_tests,
                                        30 /*average time*/};
