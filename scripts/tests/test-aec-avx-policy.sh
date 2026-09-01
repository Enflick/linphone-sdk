#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURE="${SCRIPT_DIR}/aec_avx_policy_fixture.cc"
CMAKE_FILE="${REPO_ROOT}/mswebrtc/CMakeLists.txt"
AEC_IMPL_FILE="${REPO_ROOT}/mswebrtc/mswebrtc_aec3.cc"
EXPECTED_HEADER="${REPO_ROOT}/mswebrtc/mswebrtc_cpu_policy.h"
EXPECTED_IMPL="${REPO_ROOT}/mswebrtc/mswebrtc_cpu_policy.cc"
AEC3_COMMON_HEADER="${REPO_ROOT}/mswebrtc/modules/audio_processing/aec3/aec3_common.h"
AEC3_COMMON_IMPL="${REPO_ROOT}/mswebrtc/modules/audio_processing/aec3/aec3_common.cc"
CPU_FEATURES_IMPL="${REPO_ROOT}/mswebrtc/system_wrappers/source/cpu_features.cc"
TEST_ROOT="$(mktemp -d)"
BUILD_DIR="${TEST_ROOT}/build"

cleanup() {
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${BUILD_DIR}"

failures=()

record_failure() {
  local message="$1"
  failures+=("${message}")
  printf 'FAIL: %s\n' "${message}" >&2
}

assert_absent() {
  local pattern="$1"
  local description="$2"
  if grep -Fq -- "${pattern}" "${CMAKE_FILE}"; then
    record_failure "${description}"
  fi
}

assert_scoped_avx2_sources() {
  local scoped_blocks
  scoped_blocks="$(
    awk '
      /set_source_files_properties\(/ || /set_property\(SOURCE / {capture=1}
      capture {print}
      capture && /\)/ {capture=0}
    ' "${CMAKE_FILE}"
  )"

  local avx2_source_patterns=(
    "common_audio/resampler/sinc_resampler_avx2.cc|\\\${CMAKE_CURRENT_SOURCE_DIR}/common_audio/resampler/sinc_resampler_avx2.cc"
    "adaptive_fir_filter_avx2.cc|\\\${AEC3_SRC_DIR}/adaptive_fir_filter_avx2.cc"
    "adaptive_fir_filter_erl_avx2.cc|\\\${AEC3_SRC_DIR}/adaptive_fir_filter_erl_avx2.cc"
    "fft_data_avx2.cc|\\\${AEC3_SRC_DIR}/fft_data_avx2.cc"
    "matched_filter_avx2.cc|\\\${AEC3_SRC_DIR}/matched_filter_avx2.cc"
    "vector_math_avx2.cc|\\\${AEC3_SRC_DIR}/vector_math_avx2.cc"
  )

  local source_pattern
  for source_pattern in "${avx2_source_patterns[@]}"; do
    local label="${source_pattern%%|*}"
    if ! grep -Eq -- "${source_pattern}" "${CMAKE_FILE}"; then
      record_failure "Expected AVX2 source is missing from mswebrtc/CMakeLists.txt: ${label}"
      continue
    fi
    if ! grep -Eq -- "${source_pattern}" <<<"${scoped_blocks}"; then
      record_failure "AVX2 compile flags are not source-scoped for ${label}"
    fi
  done

  if ! grep -Eq -- '(-mavx2|-mfma|/arch:AVX2)' <<<"${scoped_blocks}"; then
    record_failure "AVX2 source-scoped blocks do not carry AVX2/FMA compiler flag intent"
  fi
}

assert_i386_cpuid_subleaf_is_zeroed() {
  local zeroed_ecx_count
  zeroed_ecx_count="$(grep -Fc '"c"(0)' "${CPU_FEATURES_IMPL}" || true)"
  if [ "${zeroed_ecx_count}" -lt 2 ]; then
    record_failure "i386 PIC CPUID does not explicitly select subleaf zero"
  fi
}

compile_fixture() {
  local object_file="${BUILD_DIR}/aec_avx_policy_fixture.o"
  local binary_file="${BUILD_DIR}/aec_avx_policy_fixture"
  local compile_log="${BUILD_DIR}/compile.log"
  local link_log="${BUILD_DIR}/link.log"

  if ! c++ -std=c++17 -Wall -Wextra -Werror \
      -I"${REPO_ROOT}/mswebrtc" \
      -c "${FIXTURE}" \
      -o "${object_file}" \
      >"${compile_log}" 2>&1; then
    record_failure "AEC3 optimization fixture does not compile"
    sed -n '1,40p' "${compile_log}" >&2
    return
  fi

  if ! c++ -std=c++17 -Wall -Wextra -Werror \
      -DNDEBUG \
      -I"${REPO_ROOT}/mswebrtc" \
      -I"${REPO_ROOT}/mswebrtc/third_party/abseil-cpp" \
      "${FIXTURE}" \
      "${AEC3_COMMON_IMPL}" \
      "${CPU_FEATURES_IMPL}" \
      -o "${binary_file}" \
      >"${link_log}" 2>&1; then
    record_failure "AEC3 optimization fixture does not link"
    sed -n '1,40p' "${link_log}" >&2
    return
  fi

  if ! "${binary_file}"; then
    record_failure "CPU-policy fixture compiled but policy assertions failed"
  fi
}

compile_fixture

if grep -Fq 'GetSoftwareAecPolicy()' "${AEC_IMPL_FILE}"; then
  record_failure "MSWebRTCAEC still bypasses before AEC3 runtime dispatch"
fi
if grep -Fq 'mswebrtc_cpu_policy.cc' "${CMAKE_FILE}"; then
  record_failure "Obsolete pre-AEC3 bypass policy is still built"
fi
if [ -f "${EXPECTED_HEADER}" ] || [ -f "${EXPECTED_IMPL}" ]; then
  record_failure "Obsolete pre-AEC3 bypass policy files are still present"
fi
if ! grep -Fq 'GetCPUInfo(kFMA3)' "${AEC3_COMMON_IMPL}"; then
  record_failure "AEC3 AVX2 dispatch is not gated on FMA3"
fi

assert_absent 'target_compile_options(mswebrtc PRIVATE "/arch:AVX2")' \
  'mswebrtc target still applies /arch:AVX2 globally'
assert_absent 'target_compile_options(mswebrtc PRIVATE -mavx2)' \
  'mswebrtc target still applies -mavx2 globally'
assert_absent 'target_compile_options(mswebrtc PRIVATE -mfma)' \
  'mswebrtc target still applies -mfma globally'

assert_scoped_avx2_sources
assert_i386_cpuid_subleaf_is_zeroed

if [ "${#failures[@]}" -ne 0 ]; then
  printf '\nRED: %d contract failure(s) detected.\n' "${#failures[@]}" >&2
  exit 1
fi

echo "AEC AVX policy contract passed"
