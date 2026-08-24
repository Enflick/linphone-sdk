#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN="${REPO_ROOT}/cmake/toolchains/toolchain-android-common.cmake"

# The correction must run after the NDK legacy toolchain has populated the
# Android C compiler, and before CMake enables ASM in the parent project.
ndk_include_line="$(grep -nF 'android-legacy.toolchain.cmake' "${TOOLCHAIN}" | cut -d: -f1)"
asm_compiler_line="$(grep -nF 'set(CMAKE_ASM_COMPILER "${CMAKE_C_COMPILER}" CACHE FILEPATH' "${TOOLCHAIN}" | cut -d: -f1)"
[ -n "${ndk_include_line}" ]
[ -n "${asm_compiler_line}" ]
[ "${ndk_include_line}" -lt "${asm_compiler_line}" ]

# ASM must use the configured Android Clang driver, never a host assembler or
# the workflow's host-only Zig wrapper.
grep -Fq 'set(CMAKE_ASM_COMPILER "${CMAKE_C_COMPILER}" CACHE FILEPATH' "${TOOLCHAIN}"
! grep -Eq 'set\(CMAKE_ASM_COMPILER[[:space:]]+as([[:space:]]|\))' "${TOOLCHAIN}"
! grep -Fq 'zig-host' "${TOOLCHAIN}"

# CMake does not automatically carry the Android C compiler target and
# sysroot into ASM compiler detection.
grep -Fq 'set(CMAKE_ASM_COMPILER_TARGET "${CMAKE_C_COMPILER_TARGET}" CACHE STRING' "${TOOLCHAIN}"
grep -Fq 'set(CMAKE_ASM_FLAGS_INIT "${CMAKE_C_FLAGS_INIT}")' "${TOOLCHAIN}"
grep -Fq 'string(APPEND CMAKE_ASM_FLAGS_INIT " --target=${CMAKE_C_COMPILER_TARGET}")' "${TOOLCHAIN}"
grep -Fq 'string(APPEND CMAKE_ASM_FLAGS_INIT " --sysroot=${CMAKE_SYSROOT}")' "${TOOLCHAIN}"

for abi_toolchain in \
  toolchain-android-arm64.cmake \
  toolchain-android-armv7.cmake \
  toolchain-android-x86.cmake \
  toolchain-android-x86_64.cmake; do
  grep -Fq 'include("${CMAKE_CURRENT_LIST_DIR}/toolchain-android-common.cmake")' \
    "${REPO_ROOT}/cmake/toolchains/${abi_toolchain}"
done

echo "Android ASM toolchain contract passed"
