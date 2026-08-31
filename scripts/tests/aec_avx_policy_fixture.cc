#include "mswebrtc/mswebrtc_cpu_policy.h"

#include <array>
#include <cstdlib>
#include <functional>
#include <iostream>

namespace {

using mswebrtc::SoftwareAecPolicy;
using webrtc::CPUFeature;

void expect_policy(const char *scenario,
                   SoftwareAecPolicy actual,
                   SoftwareAecPolicy expected) {
  if (actual != expected) {
    std::cerr << scenario << " expected " << static_cast<int>(expected)
              << " but got " << static_cast<int>(actual) << '\n';
    std::exit(1);
  }
}

int query_feature(const std::array<int, 4> &feature_values, CPUFeature feature) {
  const auto index = static_cast<std::size_t>(feature);
  if (index >= feature_values.size()) {
    std::cerr << "Unexpected CPU feature enum value: " << static_cast<int>(feature)
              << '\n';
    std::exit(1);
  }
  return feature_values[index];
}

}  // namespace

int main() {
  const std::array<int, 4> no_avx2_features = {
      1,  // kSSE2
      1,  // kSSE3
      0,  // kAVX2
      0,  // kFMA3
  };
  const std::array<int, 4> avx2_features = {
      1,  // kSSE2
      1,  // kSSE3
      1,  // kAVX2
      1,  // kFMA3
  };
  const auto no_avx2_query = [&](CPUFeature feature) {
    return query_feature(no_avx2_features, feature);
  };
  const auto avx2_query = [&](CPUFeature feature) {
    return query_feature(avx2_features, feature);
  };

  expect_policy("x86 without AVX2/FMA3 bypasses software AEC",
                mswebrtc::GetSoftwareAecPolicy(/*is_x86_family=*/true, no_avx2_query),
                SoftwareAecPolicy::kBypassRequired);
  expect_policy("x86 with AVX2/FMA3 keeps software AEC enabled",
                mswebrtc::GetSoftwareAecPolicy(/*is_x86_family=*/true, avx2_query),
                SoftwareAecPolicy::kSupported);
  expect_policy("non-x86 keeps existing software AEC behavior",
                mswebrtc::GetSoftwareAecPolicy(/*is_x86_family=*/false, no_avx2_query),
                SoftwareAecPolicy::kSupported);

  return 0;
}
