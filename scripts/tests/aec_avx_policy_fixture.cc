#include "modules/audio_processing/aec3/aec3_common.h"
#include "system_wrappers/include/cpu_features_wrapper.h"

#include <cstdlib>
#include <iostream>

namespace {

using webrtc::Aec3CpuFeatures;
using webrtc::Aec3Optimization;
using webrtc::CPUFeature;
using webrtc::X86CpuFeatureState;

void expect_optimization(const char *scenario,
                         Aec3Optimization actual,
                         Aec3Optimization expected) {
  if (actual != expected) {
    std::cerr << scenario << " expected " << static_cast<int>(expected)
              << " but got " << static_cast<int>(actual) << '\n';
    std::exit(1);
  }
}

void expect_cpu_feature(const char* scenario,
                        CPUFeature feature,
                        const X86CpuFeatureState& state,
                        int expected) {
  const int actual = webrtc::GetCPUInfo(feature, state);
  if (actual != expected) {
    std::cerr << scenario << " expected " << expected << " but got " << actual
              << '\n';
    std::exit(1);
  }
}

void expect_xcr0_read(const char* scenario,
                      const X86CpuFeatureState& state,
                      bool expected) {
  const bool actual = webrtc::ShouldReadX86Xcr0(state);
  if (actual != expected) {
    std::cerr << scenario << " expected " << expected << " but got " << actual
              << '\n';
    std::exit(1);
  }
}

Aec3Optimization select_x86_optimization(
    const X86CpuFeatureState& state) {
  return webrtc::SelectOptimization(
      {true, webrtc::GetCPUInfo(webrtc::kSSE2, state) != 0,
       webrtc::GetCPUInfo(webrtc::kAVX2, state) != 0,
       webrtc::GetCPUInfo(webrtc::kFMA3, state) != 0, false});
}

}  // namespace

int main() {
  const X86CpuFeatureState fully_usable_avx2 = {
      true, true, true, true, true, true, true, true, true, true};
  const X86CpuFeatureState osxsave_missing = {
      true, true, true, true, false, false, false, true, true, true};
  const X86CpuFeatureState xsave_missing = {
      true, true, true, false, true, false, false, true, true, true};
  const X86CpuFeatureState ymm_state_missing = {
      true, true, true, true, true, true, false, true, true, true};
  const X86CpuFeatureState fma_without_avx = {
      true, true, false, true, true, true, true, true, true, true};

  expect_cpu_feature("usable AVX2 state enables AVX2", webrtc::kAVX2,
                     fully_usable_avx2, 1);
  expect_cpu_feature("usable AVX state enables FMA3", webrtc::kFMA3,
                     fully_usable_avx2, 1);
  expect_cpu_feature("missing OSXSAVE disables AVX2", webrtc::kAVX2,
                     osxsave_missing, 0);
  expect_cpu_feature("missing OSXSAVE disables FMA3", webrtc::kFMA3,
                     osxsave_missing, 0);
  expect_cpu_feature("missing YMM state disables AVX2", webrtc::kAVX2,
                     ymm_state_missing, 0);
  expect_cpu_feature("missing YMM state disables FMA3", webrtc::kFMA3,
                     ymm_state_missing, 0);
  expect_cpu_feature("FMA3 CPUID without AVX disables FMA3", webrtc::kFMA3,
                     fma_without_avx, 0);
  expect_xcr0_read("usable AVX state reads XCR0", fully_usable_avx2, true);
  expect_xcr0_read("missing XSAVE does not read XCR0", xsave_missing, false);
  expect_xcr0_read("missing OSXSAVE does not read XCR0", osxsave_missing,
                   false);
  expect_xcr0_read("missing AVX does not read XCR0", fma_without_avx, false);
  expect_optimization("raw usable state selects AVX2",
                      select_x86_optimization(fully_usable_avx2),
                      Aec3Optimization::kAvx2);
  expect_optimization("raw missing OSXSAVE state selects SSE2",
                      select_x86_optimization(osxsave_missing),
                      Aec3Optimization::kSse2);
  expect_optimization("raw missing YMM state selects SSE2",
                      select_x86_optimization(ymm_state_missing),
                      Aec3Optimization::kSse2);
  expect_optimization("raw FMA without AVX state selects SSE2",
                      select_x86_optimization(fma_without_avx),
                      Aec3Optimization::kSse2);

  expect_optimization("capable x86 uses AVX2/FMA3",
                      webrtc::SelectOptimization({true, true, true, true, false}),
                      Aec3Optimization::kAvx2);
  expect_optimization("no-AVX x86 uses SSE2",
                      webrtc::SelectOptimization({true, true, false, false, false}),
                      Aec3Optimization::kSse2);
  expect_optimization("x86 without SSE2 uses scalar",
                      webrtc::SelectOptimization({true, false, false, false, false}),
                      Aec3Optimization::kNone);
  expect_optimization("non-x86 without NEON uses scalar",
                      webrtc::SelectOptimization({false, false, false, false, false}),
                      Aec3Optimization::kNone);
  expect_optimization("ARM keeps NEON behavior",
                      webrtc::SelectOptimization({false, false, false, false, true}),
                      Aec3Optimization::kNeon);
  expect_optimization("AVX2 without FMA3 falls back safely",
                      webrtc::SelectOptimization({true, true, true, false, false}),
                      Aec3Optimization::kSse2);
  expect_optimization("FMA3 CPUID without usable AVX OS state falls back safely",
                      webrtc::SelectOptimization({true, true, false, true, false}),
                      Aec3Optimization::kSse2);
  expect_optimization("contradictory AVX2 without SSE2 falls back to scalar",
                      webrtc::SelectOptimization({true, false, true, true, false}),
                      Aec3Optimization::kNone);

  return 0;
}
