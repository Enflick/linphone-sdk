#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURE="${SCRIPT_DIR}/aec_avx_policy_fixture.cc"
CMAKE_FILE="${REPO_ROOT}/mswebrtc/CMakeLists.txt"
AEC_IMPL_FILE="${REPO_ROOT}/mswebrtc/mswebrtc_aec3.cc"
EXPECTED_HEADER="${REPO_ROOT}/mswebrtc/mswebrtc_cpu_policy.h"
EXPECTED_IMPL="${REPO_ROOT}/mswebrtc/mswebrtc_cpu_policy.cc"
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

assert_policy_precedes_echo_canceller_construction() {
  local policy_line
  local construct_line
  local guard_block

  policy_line="$(grep -n 'GetSoftwareAecPolicy()' "${AEC_IMPL_FILE}" | head -1 | cut -d: -f1)"
  construct_line="$(grep -n 'std::make_unique<webrtc::EchoCanceller3>' "${AEC_IMPL_FILE}" | head -1 | cut -d: -f1)"

  if [ -z "${policy_line}" ]; then
    record_failure "MSWebRTCAEC preprocess does not call GetSoftwareAecPolicy()"
    return
  fi
  if [ -z "${construct_line}" ]; then
    record_failure "MSWebRTCAEC preprocess no longer constructs EchoCanceller3 where expected"
    return
  fi
  if [ "${policy_line}" -ge "${construct_line}" ]; then
    record_failure "CPU policy check must occur before EchoCanceller3 construction"
    return
  fi

  guard_block="$(sed -n "${policy_line},$((construct_line - 1))p" "${AEC_IMPL_FILE}")"
  if ! grep -Fq 'mBypassMode = true;' <<<"${guard_block}"; then
    record_failure "CPU policy guard does not force bypass before EchoCanceller3 construction"
  fi
  if ! grep -Eq '^.*return;$' <<<"${guard_block}"; then
    record_failure "CPU policy guard does not return before EchoCanceller3 construction"
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
    record_failure "CPU-policy fixture does not compile. Expected seam files: mswebrtc/mswebrtc_cpu_policy.h and GetSoftwareAecPolicy(bool, query)"
    sed -n '1,40p' "${compile_log}" >&2
    return
  fi

  if ! c++ -std=c++17 -Wall -Wextra -Werror \
      -I"${REPO_ROOT}/mswebrtc" \
      "${FIXTURE}" \
      "${EXPECTED_IMPL}" \
      -o "${binary_file}" \
      >"${link_log}" 2>&1; then
    record_failure "CPU-policy fixture does not link against ${EXPECTED_IMPL}"
    sed -n '1,40p' "${link_log}" >&2
    return
  fi

  if ! "${binary_file}"; then
    record_failure "CPU-policy fixture compiled but policy assertions failed"
  fi
}

compile_fixture

if [ ! -f "${EXPECTED_HEADER}" ]; then
  record_failure "Missing expected CPU-policy header ${EXPECTED_HEADER}"
fi
if [ ! -f "${EXPECTED_IMPL}" ]; then
  record_failure "Missing expected CPU-policy implementation ${EXPECTED_IMPL}"
fi

assert_policy_precedes_echo_canceller_construction

assert_absent 'target_compile_options(mswebrtc PRIVATE "/arch:AVX2")' \
  'mswebrtc target still applies /arch:AVX2 globally'
assert_absent 'target_compile_options(mswebrtc PRIVATE -mavx2)' \
  'mswebrtc target still applies -mavx2 globally'
assert_absent 'target_compile_options(mswebrtc PRIVATE -mfma)' \
  'mswebrtc target still applies -mfma globally'

assert_scoped_avx2_sources

if [ "${#failures[@]}" -ne 0 ]; then
  printf '\nRED: %d contract failure(s) detected.\n' "${#failures[@]}" >&2
  exit 1
fi

echo "AEC AVX policy contract passed"
