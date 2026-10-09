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

#include "sal/ping-op.h"

using namespace std;

LINPHONE_BEGIN_NAMESPACE

void SalPingOp::notifyResult() {
	// A released op belongs to a ping that was replaced or whose account went away.
	if (mResultNotified || mOpReleased) return;
	mResultNotified = true;
	mState = State::Terminated;
	if (mResultCb) mResultCb(this);
}

void SalPingOp::processIoErrorCb(void *userCtx, BCTBX_UNUSED(const belle_sip_io_error_event_t *event)) {
	auto op = static_cast<SalPingOp *>(userCtx);
	sal_error_info_set(&op->mErrorInfo, SalReasonIOError, "SIP", 0, "IO Error", nullptr);
	// sal_error_info_set() turns 0 into 503; keep 0 so a real 503 response stays distinguishable.
	op->mErrorInfo.protocol_code = 0;
	op->notifyResult();
}

void SalPingOp::processResponseEventCb(void *userCtx, const belle_sip_response_event_t *event) {
	auto op = static_cast<SalPingOp *>(userCtx);
	auto response = belle_sip_response_event_get_response(event);
	if (belle_sip_response_get_status_code(response) < 200) return;
	op->setErrorInfoFromResponse(response);
	op->notifyResult();
}

void SalPingOp::processTimeoutCb(void *userCtx, BCTBX_UNUSED(const belle_sip_timeout_event_t *event)) {
	auto op = static_cast<SalPingOp *>(userCtx);
	sal_error_info_set(&op->mErrorInfo, SalReasonRequestTimeout, "SIP", 0, "Request timeout", nullptr);
	// Same as above: a real 408 response keeps its code.
	op->mErrorInfo.protocol_code = 0;
	op->notifyResult();
}

void SalPingOp::fillCallbacks() {
	static belle_sip_listener_callbacks_t opPingCallbacks = {0};
	if (!opPingCallbacks.process_io_error) {
		opPingCallbacks.process_io_error = processIoErrorCb;
		opPingCallbacks.process_response_event = processResponseEventCb;
		opPingCallbacks.process_timeout = processTimeoutCb;
	}
	mCallbacks = &opPingCallbacks;
}

SalPingOp::SalPingOp(Sal *sal) : SalOp(sal) {
	mType = Type::Ping;
	fillCallbacks();
}

int SalPingOp::sendPing(const SalAddress *proxy, const SalAddress *from) {
	mDir = Dir::Outgoing;
	setFromAddress(from);
	setToAddress(proxy);
	// Same next hop as SalRegisterOp::sendRegister(), so the ping goes out on the registration's connection.
	setRouteAddress(proxy);
	return sendRequest(buildRequest("OPTIONS"));
}

LINPHONE_END_NAMESPACE
