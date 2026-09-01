/*
 *  Copyright (c) 2011 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

// Parts of this file derived from Chromium's base/cpu.cc.

#include "rtc_base/system/arch.h"
#include "system_wrappers/include/cpu_features_wrapper.h"

#if defined(WEBRTC_ARCH_X86_FAMILY) && defined(_MSC_VER)
#include <intrin.h>
#endif

namespace webrtc {

bool ShouldReadX86Xcr0(const X86CpuFeatureState& state) {
  return state.has_avx && state.has_xsave && state.has_osxsave;
}

namespace {

bool HasUsableAvxState(const X86CpuFeatureState& state) {
  return state.has_avx && state.has_xsave && state.has_osxsave &&
         state.has_xmm_state && state.has_ymm_state;
}

}  // namespace

int GetCPUInfo(CPUFeature feature, const X86CpuFeatureState& state) {
  switch (feature) {
    case kSSE2:
      return state.has_sse2;
    case kSSE3:
      return state.has_sse3;
    case kAVX2:
      return HasUsableAvxState(state) && state.has_avx2 && state.has_bmi2;
    case kFMA3:
      return HasUsableAvxState(state) && state.has_fma3;
  }
  return 0;
}

// No CPU feature is available => straight C path.
int GetCPUInfoNoASM(CPUFeature feature) {
  (void)feature;
  return 0;
}

#if defined(WEBRTC_ARCH_X86_FAMILY)

#if defined(WEBRTC_ENABLE_AVX2)
// xgetbv returns the value of an Intel Extended Control Register (XCR).
// Currently only XCR0 is defined by Intel so `xcr` should always be zero.
static uint64_t xgetbv(uint32_t xcr) {
#if defined(_MSC_VER)
  return _xgetbv(xcr);
#else
  uint32_t eax, edx;

  __asm__ volatile("xgetbv" : "=a"(eax), "=d"(edx) : "c"(xcr));
  return (static_cast<uint64_t>(edx) << 32) | eax;
#endif  // _MSC_VER
}
#endif  // WEBRTC_ENABLE_AVX2

#ifndef _MSC_VER
// Intrinsic for "cpuid".
#if defined(__pic__) && defined(__i386__)
static inline void __cpuid(int cpu_info[4], int info_type) {
  __asm__ volatile(
      "mov %%ebx, %%edi\n"
      "cpuid\n"
      "xchg %%edi, %%ebx\n"
      : "=a"(cpu_info[0]), "=D"(cpu_info[1]), "=c"(cpu_info[2]),
        "=d"(cpu_info[3])
      : "a"(info_type), "c"(0));
}
#else
static inline void __cpuid(int cpu_info[4], int info_type) {
  __asm__ volatile("cpuid\n"
                   : "=a"(cpu_info[0]), "=b"(cpu_info[1]), "=c"(cpu_info[2]),
                     "=d"(cpu_info[3])
                   : "a"(info_type), "c"(0));
}
#endif
#endif  // _MSC_VER
#endif  // WEBRTC_ARCH_X86_FAMILY

#if defined(WEBRTC_ARCH_X86_FAMILY)
// Actual feature detection for x86.
int GetCPUInfo(CPUFeature feature) {
  int cpu_info[4];
  __cpuid(cpu_info, 1);
  X86CpuFeatureState state = {};
  state.has_sse2 = (cpu_info[3] & 0x04000000) != 0;
  state.has_sse3 = (cpu_info[2] & 0x00000001) != 0;

  if (feature == kSSE2 || feature == kSSE3) {
    return GetCPUInfo(feature, state);
  }
#if defined(WEBRTC_ENABLE_AVX2)
  if (feature == kAVX2 || feature == kFMA3) {
    state.has_avx = (cpu_info[2] & 0x10000000) != 0;
    state.has_xsave = (cpu_info[2] & 0x04000000) != 0;
    state.has_osxsave = (cpu_info[2] & 0x08000000) != 0;
    state.has_fma3 = (cpu_info[2] & 0x00001000) != 0;

    if (ShouldReadX86Xcr0(state)) {
      const uint64_t xcr0 = xgetbv(0);
      state.has_xmm_state = (xcr0 & 0x00000002) != 0;
      state.has_ymm_state = (xcr0 & 0x00000004) != 0;
    }

    int cpu_info7[4];
    __cpuid(cpu_info7, 0);
    int num_ids = cpu_info7[0];
    if (num_ids >= 7) {
      __cpuid(cpu_info7, 7);
      state.has_avx2 = (cpu_info7[1] & 0x00000020) != 0;
      state.has_bmi2 = (cpu_info7[1] & 0x00000100) != 0;
    }

    return GetCPUInfo(feature, state);
  }
#endif  // WEBRTC_ENABLE_AVX2
  return 0;
}
#else
// Default to straight C for other platforms.
int GetCPUInfo(CPUFeature feature) {
  (void)feature;
  return 0;
}
#endif

}  // namespace webrtc
