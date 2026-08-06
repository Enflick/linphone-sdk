/*
 * Copyright (c) 2010-2022 Belledonne Communications SARL.
 *
 * This file is part of mediastreamer2
 * (see https://gitlab.linphone.org/BC/public/mediastreamer2).
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

/* TextNow patch: decoded downlink audio tap — see msdecodedaudiotap.h. */

#include "mediastreamer2/msdecodedaudiotap.h"

typedef struct _DecodedAudioTapData {
	MSDecodedAudioTapCallback cb;
	void *user_data;
	const void *stream_id; /* opaque identity of the owning AudioStream */
	int sample_rate;
	int nchannels;
} DecodedAudioTapData;

/* Process-wide registration. Written by the application before streams are
 * start (typically once at startup, next to Core configuration); read when
 * a stream starts. Each stream's filter keeps its own copy, so a
 * late re-registration never races a running ticker. */
static MSDecodedAudioTapCallback s_tap_cb = NULL;
static void *s_tap_user_data = NULL;

void ms_set_global_decoded_audio_tap(MSDecodedAudioTapCallback cb, void *user_data) {
	s_tap_user_data = user_data;
	s_tap_cb = cb;
}

bool_t ms_get_global_decoded_audio_tap(MSDecodedAudioTapCallback *cb, void **user_data) {
	if (cb) *cb = s_tap_cb;
	if (user_data) *user_data = s_tap_user_data;
	return s_tap_cb != NULL;
}

static void tap_init(MSFilter *f) {
	f->data = ms_new0(DecodedAudioTapData, 1);
}

static void tap_uninit(MSFilter *f) {
	ms_free(f->data);
}

/* Runs on the MSTicker thread. Forwards every block untouched (zero-copy)
 * and hands the PCM to the callback. MUST NOT allocate or block. */
static void tap_process(MSFilter *f) {
	DecodedAudioTapData *d = (DecodedAudioTapData *)f->data;
	mblk_t *im;
	while ((im = ms_queue_get(f->inputs[0])) != NULL) {
		if (d->cb) {
			const mblk_t *cur;
			for (cur = im; cur != NULL; cur = cur->b_cont) {
				size_t bytes = (size_t)(cur->b_wptr - cur->b_rptr);
				if (bytes >= sizeof(int16_t)) {
					d->cb(d->user_data, d->stream_id, (const int16_t *)cur->b_rptr, bytes / sizeof(int16_t),
					      d->sample_rate, d->nchannels);
				}
			}
		}
		ms_queue_put(f->outputs[0], im);
	}
}

static int tap_set_sample_rate(MSFilter *f, void *arg) {
	((DecodedAudioTapData *)f->data)->sample_rate = *(int *)arg;
	return 0;
}

static int tap_get_sample_rate(MSFilter *f, void *arg) {
	*(int *)arg = ((DecodedAudioTapData *)f->data)->sample_rate;
	return 0;
}

static int tap_set_nchannels(MSFilter *f, void *arg) {
	((DecodedAudioTapData *)f->data)->nchannels = *(int *)arg;
	return 0;
}

static int tap_get_nchannels(MSFilter *f, void *arg) {
	*(int *)arg = ((DecodedAudioTapData *)f->data)->nchannels;
	return 0;
}

static MSFilterMethod tap_methods[] = {{MS_FILTER_SET_SAMPLE_RATE, tap_set_sample_rate},
                                       {MS_FILTER_GET_SAMPLE_RATE, tap_get_sample_rate},
                                       {MS_FILTER_SET_NCHANNELS, tap_set_nchannels},
                                       {MS_FILTER_GET_NCHANNELS, tap_get_nchannels},
                                       {0, NULL}};

#ifdef _MSC_VER

static MSFilterDesc ms_decoded_audio_tap_desc = {
    MS_FILTER_PLUGIN_ID,
    "MSDecodedAudioTap",
    N_("Pass-through tap handing decoded downlink PCM to an application callback."),
    MS_FILTER_OTHER,
    NULL,
    1,
    1,
    tap_init,
    NULL,
    tap_process,
    NULL,
    tap_uninit,
    tap_methods};

#else

static MSFilterDesc ms_decoded_audio_tap_desc = {
    .id = MS_FILTER_PLUGIN_ID,
    .name = "MSDecodedAudioTap",
    .text = N_("Pass-through tap handing decoded downlink PCM to an application callback."),
    .category = MS_FILTER_OTHER,
    .ninputs = 1,
    .noutputs = 1,
    .init = tap_init,
    .process = tap_process,
    .uninit = tap_uninit,
    .methods = tap_methods};

#endif

MSFilter *ms_decoded_audio_tap_create_filter(MSFactory *factory,
                                             MSDecodedAudioTapCallback cb,
                                             void *user_data,
                                             const void *stream_id,
                                             int sample_rate,
                                             int nchannels) {
	MSFilter *f = ms_factory_create_filter_from_desc(factory, &ms_decoded_audio_tap_desc);
	if (f != NULL) {
		DecodedAudioTapData *d = (DecodedAudioTapData *)f->data;
		d->cb = cb;
		d->user_data = user_data;
		d->stream_id = stream_id;
		d->sample_rate = sample_rate;
		d->nchannels = nchannels;
	}
	return f;
}
