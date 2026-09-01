/*
 *  Copyright (c) 2017 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#include "modules/audio_processing/aec3/aec3_common.h"

#include <stdint.h>

#include "rtc_base/checks.h"
#include "rtc_base/system/arch.h"
#include "system_wrappers/include/cpu_features_wrapper.h"

namespace webrtc {

Aec3Optimization SelectOptimization(const Aec3CpuFeatures& features) {
  if (features.is_x86_family) {
    if (features.has_sse2 && features.has_avx2 && features.has_fma3) {
      return Aec3Optimization::kAvx2;
    }
    if (features.has_sse2) {
      return Aec3Optimization::kSse2;
    }
    return Aec3Optimization::kNone;
  }

  return features.has_neon ? Aec3Optimization::kNeon
                           : Aec3Optimization::kNone;
}

Aec3Optimization DetectOptimization() {
  Aec3CpuFeatures features = {};

#if defined(WEBRTC_ARCH_X86_FAMILY)
  features.is_x86_family = true;
  features.has_sse2 = GetCPUInfo(kSSE2) != 0;
  features.has_avx2 = GetCPUInfo(kAVX2) != 0;
  features.has_fma3 = features.has_avx2 && GetCPUInfo(kFMA3) != 0;
#elif defined(WEBRTC_HAS_NEON)
  features.has_neon = true;
#endif

  return SelectOptimization(features);
}

float FastApproxLog2f(const float in) {
  RTC_DCHECK_GT(in, .0f);
  // Read and interpret float as uint32_t and then cast to float.
  // This is done to extract the exponent (bits 30 - 23).
  // "Right shift" of the exponent is then performed by multiplying
  // with the constant (1/2^23). Finally, we subtract a constant to
  // remove the bias (https://en.wikipedia.org/wiki/Exponent_bias).
  union {
    float dummy;
    uint32_t a;
  } x = {in};
  float out = x.a;
  out *= 1.1920929e-7f;  // 1/2^23
  out -= 126.942695f;    // Remove bias.
  return out;
}

float Log2TodB(const float in_log2) {
  return 3.0102999566398121 * in_log2;
}

}  // namespace webrtc
