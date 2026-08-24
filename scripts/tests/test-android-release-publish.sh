#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
BUILD_DIR="${TEST_ROOT}/build"
STAGING_DIR="${TEST_ROOT}/staging"
REMOTE_DIR="${TEST_ROOT}/remote"
PORT_FILE="${TEST_ROOT}/port"
VERSION="5.5.12-$(git -C "$REPO_ROOT" rev-parse --short=9 HEAD)"
ARTIFACT_IDS=(linphone-sdk-android linphone-sdk-android-debug)

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$REMOTE_DIR"

# Keep the Android runner independent of the optional gh CLI while requiring
# authenticated, bounded, HTTPS-only access to the exact release asset.
ANDROID_WORKFLOW="${REPO_ROOT}/.github/workflows/android-release-publish.yml"
grep -Fq 'ANDROID_ARCHS="${ANDROID_ARCHS:-arm64,armv7,x86,x86_64}"' "${REPO_ROOT}/scripts/android-release-publish.sh"
grep -Fq 'linphonesdk_dependent_option("AV1"' "${REPO_ROOT}/cmake/Options.cmake"
for disabled_flag in \
  ENABLE_GPL_THIRD_PARTIES ENABLE_NON_FREE_FEATURES ENABLE_VIDEO ENABLE_ADVANCED_IM \
  ENABLE_DB_STORAGE ENABLE_VCARD ENABLE_MKV ENABLE_LDAP ENABLE_JPEG ENABLE_QRCODE \
  ENABLE_FLEXIAPI ENABLE_LIME ENABLE_LIME_X3DH ENABLE_GSM ENABLE_AV1 ENABLE_VPX \
  ENABLE_LIBYUV ENABLE_CAMERA2 ENABLE_DOC; do
  grep -Fq "  -D${disabled_flag}=OFF" "${REPO_ROOT}/scripts/android-release-publish.sh"
done
for enabled_flag in ENABLE_AAUDIO ENABLE_OPENSLES ENABLE_WEBRTC_AEC; do
  grep -Fq "  -D${enabled_flag}=ON" "${REPO_ROOT}/scripts/android-release-publish.sh"
done
grep -Fq '"${ANDROID_RELEASE_CMAKE_FLAGS[@]}"' "${REPO_ROOT}/scripts/android-release-publish.sh"
grep -Fq "LINPHONE_ANDROID_BUILD_JOBS: '2'" "$ANDROID_WORKFLOW"
grep -Fq 'release_asset_url="https://api.github.com/repos/Enflick/linphone-sdk/releases/assets/509435882"' "$ANDROID_WORKFLOW"
grep -Fq 'SOURCE_BUNDLE_ASSET: linphone-submodules-5.5.12-088bab728-r2.tar.gz' "$ANDROID_WORKFLOW"
grep -Fq 'SOURCE_BUNDLE_SHA256: 1bbad0a29699b62ed398d603a4032248853d379c83cf726fbb605b5282453058' "$ANDROID_WORKFLOW"
grep -Fq 'GITHUB_TOKEN: ${{ github.token }}' "$ANDROID_WORKFLOW"
grep -Fq -- "--proto '=https'" "$ANDROID_WORKFLOW"
grep -Fq -- "--proto-redir '=https'" "$ANDROID_WORKFLOW"
grep -Fq -- "--header 'Accept: application/octet-stream'" "$ANDROID_WORKFLOW"
grep -Fq -- '--header "Authorization: Bearer ${GITHUB_TOKEN}"' "$ANDROID_WORKFLOW"
grep -Fq -- '--header '\''X-GitHub-Api-Version: 2022-11-28'\''' "$ANDROID_WORKFLOW"
grep -Fq -- '--retry 4' "$ANDROID_WORKFLOW"
grep -Fq -- '--retry-max-time 900' "$ANDROID_WORKFLOW"
grep -Fq -- '--max-time 900' "$ANDROID_WORKFLOW"
! grep -Fq 'gh release download' "$ANDROID_WORKFLOW"
! grep -Fq 'GH_TOKEN:' "$ANDROID_WORKFLOW"
! grep -Eq 'for cmd .*\bgh\b' "$ANDROID_WORKFLOW"
! grep -Eq -- '(echo|printf|tee).*GITHUB_TOKEN|--verbose' "$ANDROID_WORKFLOW"
! sed '/^  publish:/,$d' "$ANDROID_WORKFLOW" | grep -Eq '(^|[^A-Z])NEXUS_CAPI_(USER|PASSWORD)'

# Build provisioning must be pinned and credential-free; Nexus credentials are
# only allowed in the publication job below the build artifact boundary.
grep -Fq 'actions/setup-java@c1e323688fd81a25caa38c78aa6df2d33d3e20d9' "$ANDROID_WORKFLOW"
! grep -Fq 'Enflick/composite-actions' "$ANDROID_WORKFLOW"
! grep -Fq 'install-android-sdk' "$ANDROID_WORKFLOW"
grep -Fq 'ANDROID_SDK_TOOLS_URL: https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip' "$ANDROID_WORKFLOW"
grep -Fq 'ANDROID_SDK_TOOLS_SHA256: 2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258' "$ANDROID_WORKFLOW"
grep -Fq -- "--proto '=https'" "$ANDROID_WORKFLOW"
grep -Fq -- "--proto-redir '=https'" "$ANDROID_WORKFLOW"
grep -Fq -- '--retry-max-time 900' "$ANDROID_WORKFLOW"
grep -Fq -- '--max-time 900' "$ANDROID_WORKFLOW"
grep -Fq 'sha256sum --check' "$ANDROID_WORKFLOW"
grep -Fq 'sdk_root="${RUNNER_TEMP}/android-sdk"' "$ANDROID_WORKFLOW"
grep -Fq 'cmdline-tools/latest' "$ANDROID_WORKFLOW"
grep -Fq 'echo "ANDROID_HOME=${sdk_root}"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "ANDROID_SDK_ROOT=${sdk_root}"' "$ANDROID_WORKFLOW"
grep -Fq -- '--licenses' "$ANDROID_WORKFLOW"
grep -Fq 'set +o pipefail' "$ANDROID_WORKFLOW"
grep -Fq 'sdkmanager_status="${PIPESTATUS[1]}"' "$ANDROID_WORKFLOW"
grep -Fq 'set -o pipefail' "$ANDROID_WORKFLOW"
grep -Fq 'if [ "${sdkmanager_status}" -ne 0 ]; then' "$ANDROID_WORKFLOW"
grep -Fq 'if yes | "${sdkmanager}" --sdk_root="${sdk_root}" --licenses' "$ANDROID_WORKFLOW"
! grep -Fq 'status=$?' "$ANDROID_WORKFLOW"
grep -Fq 'cmake;3.22.1' "$ANDROID_WORKFLOW"
grep -Fq 'ndk;27.2.12479018' "$ANDROID_WORKFLOW"
grep -Fq 'platforms;android-34' "$ANDROID_WORKFLOW"
grep -Fq 'build-tools;34.0.0' "$ANDROID_WORKFLOW"
grep -Fq 'ANDROID_NDK_HOME=${ndk_dir}' "$ANDROID_WORKFLOW"
grep -Fq 'cmake/3.22.1/bin' "$ANDROID_WORKFLOW"
grep -Fq 'llvm_host_dir="${ndk_dir}/toolchains/llvm/prebuilt/linux-x86_64"' "$ANDROID_WORKFLOW"
grep -Fq 'llvm_bin="${llvm_host_dir}/bin"' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${llvm_bin}/clang" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${llvm_bin}/clang++" ]' "$ANDROID_WORKFLOW"
grep -Fq 'ZIG_URL: https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz' "$ANDROID_WORKFLOW"
grep -Fq 'ZIG_SHA256: d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea' "$ANDROID_WORKFLOW"
grep -Fq 'import tarfile' "$ANDROID_WORKFLOW"
grep -Fq 'secure_tar_extract="${RUNNER_TEMP}/secure-tar-extract.py"' "$ANDROID_WORKFLOW"
grep -Fq 'destination_path = os.path.realpath(destination)' "$ANDROID_WORKFLOW"
grep -Fq 'member_path = os.path.realpath(' "$ANDROID_WORKFLOW"
grep -Fq 'os.path.commonpath((destination_path, member_path))' "$ANDROID_WORKFLOW"
grep -Fq 'os.path.isabs(member_name)' "$ANDROID_WORKFLOW"
grep -Fq '".." in member_parts' "$ANDROID_WORKFLOW"
grep -Fq 'member.issym()' "$ANDROID_WORKFLOW"
grep -Fq 'member.islnk()' "$ANDROID_WORKFLOW"
grep -Fq 'member.ischr()' "$ANDROID_WORKFLOW"
grep -Fq 'member.isblk()' "$ANDROID_WORKFLOW"
grep -Fq 'member.isfifo()' "$ANDROID_WORKFLOW"
grep -Fq 'member.isdir() or member.isreg()' "$ANDROID_WORKFLOW"
grep -Fq 'validated_members = []' "$ANDROID_WORKFLOW"
! grep -Fq 'filter="data"' "$ANDROID_WORKFLOW"
zig_cleanup_line="$(grep -nF 'rm -rf "${zig_root}"' "$ANDROID_WORKFLOW" | cut -d: -f1)"
zig_extract_line="$(grep -nF 'python3 "${secure_tar_extract}" "${zig_archive}"' "$ANDROID_WORKFLOW" | head -1 | cut -d: -f1)"
[ -n "${zig_cleanup_line}" ] && [ -n "${zig_extract_line}" ] && [ "${zig_cleanup_line}" -lt "${zig_extract_line}" ]
grep -Fq '[ "$("${zig_bin}" version)" = '\''0.13.0'\'' ]' "$ANDROID_WORKFLOW"
grep -Fq 'exec \"${zig_bin}\" cc \"\$@\"' "$ANDROID_WORKFLOW"
grep -Fq 'exec \"${zig_bin}\" c++ \"\$@\"' "$ANDROID_WORKFLOW"
grep -Fq 'exec \"${zig_bin}\" ar \"\$@\"' "$ANDROID_WORKFLOW"
grep -Fq 'exec \"${zig_bin}\" ranlib \"\$@\"' "$ANDROID_WORKFLOW"
grep -Fq 'exec \"${zig_bin}\" ld.lld \"\$@\"' "$ANDROID_WORKFLOW"
grep -Fq 'chmod +x "${host_cc}" "${host_cxx}" "${host_ar}" "${host_ranlib}" "${host_ld}"' "$ANDROID_WORKFLOW"
grep -Fq '"${host_ar}" --help >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq '"${host_ranlib}" --help >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq '"${host_ld}" --version >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq '"${host_ld}" --help >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq '"${host_cc}" "${host_source}" -o "${host_binary}"' "$ANDROID_WORKFLOW"
grep -Fq '[ "$("${host_binary}")" = '\''zig-host-ok'\'' ]' "$ANDROID_WORKFLOW"
grep -Fq 'echo "CC=${host_cc}"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "CXX=${host_cxx}"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "ZIG_HOST_AR=${host_ar}"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "ZIG_HOST_RANLIB=${host_ranlib}"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "ZIG_HOST_LD=${host_ld}"' "$ANDROID_WORKFLOW"
! grep -Fq 'echo "${llvm_bin}" >> "${GITHUB_PATH}"' "$ANDROID_WORKFLOW"
grep -Fq 'DOXYGEN_URL: https://github.com/doxygen/doxygen/releases/download/Release_1_9_8/doxygen-1.9.8.linux.bin.tar.gz' "$ANDROID_WORKFLOW"
grep -Fq 'DOXYGEN_SHA256: dda773bdc62384b7d796fe8b6c5029daad72483e4c8ad4abf6ee9fb98b649388' "$ANDROID_WORKFLOW"
grep -Fq 'doxygen_archive="${RUNNER_TEMP}/doxygen-1.9.8.linux.bin.tar.gz"' "$ANDROID_WORKFLOW"
grep -Fq 'doxygen_root="${RUNNER_TEMP}/doxygen-1.9.8"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "${doxygen_root}/bin" >> "${GITHUB_PATH}"' "$ANDROID_WORKFLOW"
grep -Fq 'doxygen_version="$("${doxygen_root}/bin/doxygen" --version)"' "$ANDROID_WORKFLOW"
grep -Fq '[[ "${doxygen_version}" == 1.9.8* ]] || { echo "Doxygen 1.9.8 is required, found ${doxygen_version}"' "$ANDROID_WORKFLOW"
make_step_line="$(grep -nF 'Bootstrap pinned GNU Make' "$ANDROID_WORKFLOW" | cut -d: -f1)"
grep -Fq 'meson_version="$("${meson_bin}/meson" --version)"' "$ANDROID_WORKFLOW"
grep -Fq '[ "${meson_version}" = '\''1.5.2'\'' ]' "$ANDROID_WORKFLOW"
doxygen_cleanup_line="$(grep -nF 'rm -rf "${doxygen_root}"' "$ANDROID_WORKFLOW" | cut -d: -f1)"
doxygen_extract_line="$(grep -nF 'python3 "${RUNNER_TEMP}/secure-tar-extract.py" "${doxygen_archive}"' "$ANDROID_WORKFLOW" | tail -1 | cut -d: -f1)"
[ -n "${doxygen_cleanup_line}" ] && [ -n "${doxygen_extract_line}" ] && [ "${doxygen_cleanup_line}" -lt "${doxygen_extract_line}" ]
grep -Fq 'MAKE_URL: https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz' "$ANDROID_WORKFLOW"
grep -Fq 'MAKE_SHA256: dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3' "$ANDROID_WORKFLOW"
grep -Fq 'make_archive="${RUNNER_TEMP}/make-4.4.1.tar.gz"' "$ANDROID_WORKFLOW"
grep -Fq 'make_root="${RUNNER_TEMP}/make-4.4.1"' "$ANDROID_WORKFLOW"
grep -Fq 'make_prefix="${RUNNER_TEMP}/make-4.4.1-install"' "$ANDROID_WORKFLOW"
grep -Fq 'make_bin="${RUNNER_TEMP}/make-bin"' "$ANDROID_WORKFLOW"
grep -Fq 'python3 "${RUNNER_TEMP}/secure-tar-extract.py" "${make_archive}" "${RUNNER_TEMP}"' "$ANDROID_WORKFLOW"
grep -Fq 'CC="${CC}"' "$ANDROID_WORKFLOW"
grep -Fq 'CXX="${CXX}"' "$ANDROID_WORKFLOW"
grep -Fq 'AR="${ZIG_HOST_AR}"' "$ANDROID_WORKFLOW"
grep -Fq 'RANLIB="${ZIG_HOST_RANLIB}"' "$ANDROID_WORKFLOW"
grep -Fq 'LD="${ZIG_HOST_LD}"' "$ANDROID_WORKFLOW"
grep -Fq 'cd "${make_root}"' "$ANDROID_WORKFLOW"
grep -Fq './configure --disable-nls --disable-dependency-tracking --prefix="${make_prefix}"' "$ANDROID_WORKFLOW"
grep -Fq 'sh build.sh' "$ANDROID_WORKFLOW"
! grep -Fq '"${make_root}/configure"' "$ANDROID_WORKFLOW"
make_cd_line="$(grep -nF 'cd "${make_root}"' "$ANDROID_WORKFLOW" | tail -1 | cut -d: -f1)"
make_configure_line="$(grep -nF './configure --disable-nls --disable-dependency-tracking --prefix="${make_prefix}"' "$ANDROID_WORKFLOW" | tail -1 | cut -d: -f1)"
make_build_line="$(grep -nF 'sh build.sh' "$ANDROID_WORKFLOW" | tail -1 | cut -d: -f1)"
[ -n "${make_cd_line}" ] && [ -n "${make_configure_line}" ] && [ -n "${make_build_line}" ]
[ "${make_cd_line}" -lt "${make_configure_line}" ]
[ "${make_configure_line}" -lt "${make_build_line}" ]
make_bootstrap_block="$(sed -n "${make_cd_line},${make_build_line}p" "$ANDROID_WORKFLOW")"
grep -Fq 'CC="${CC}" \' <<< "${make_bootstrap_block}"
grep -Fq 'CXX="${CXX}" \' <<< "${make_bootstrap_block}"
grep -Fq 'AR="${ZIG_HOST_AR}" \' <<< "${make_bootstrap_block}"
grep -Fq 'RANLIB="${ZIG_HOST_RANLIB}" \' <<< "${make_bootstrap_block}"
grep -Fq 'LD="${ZIG_HOST_LD}" \' <<< "${make_bootstrap_block}"
grep -Fq 'install -m 0755 "${make_root}/make" "${make_bin}/make"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "${make_bin}" >> "${GITHUB_PATH}"' "$ANDROID_WORKFLOW"
grep -Fq 'make_version="$("${make_bin}/make" --version | sed -n '\''1p'\'')"' "$ANDROID_WORKFLOW"
grep -Fq 'for cmd in cmake curl doxygen git java javac make meson ninja perl python3 shasum sha256sum tar unzip; do' "$ANDROID_WORKFLOW"
grep -Fq 'make --version | sed -n '\''1p'\'' | grep -Fq '\''GNU Make 4.4.1'\''' "$ANDROID_WORKFLOW"
grep -Fq 'doxygen_version="$(doxygen --version)"' "$ANDROID_WORKFLOW"
grep -Fq '[[ "${doxygen_version}" == 1.9.8* ]] || { echo "Doxygen 1.9.8 is required, found ${doxygen_version}"' "$ANDROID_WORKFLOW"
! grep -Eq '(^|[^[:alnum:]_])(nasm|yasm)([^[:alnum:]_]|$)' "$ANDROID_WORKFLOW"
grep -Fq '[ "${CC}" = "${RUNNER_TEMP}/zig-host-cc" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ "${CXX}" = "${RUNNER_TEMP}/zig-host-cxx" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ "${ZIG_HOST_LD}" = "${RUNNER_TEMP}/zig-host-ld" ]' "$ANDROID_WORKFLOW"
! grep -Fq 'CC=${llvm_bin}/clang' "$ANDROID_WORKFLOW"
! grep -Fq 'CXX=${llvm_bin}/clang++' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${CC}" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${CXX}" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${ZIG_HOST_AR}" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${ZIG_HOST_RANLIB}" ]' "$ANDROID_WORKFLOW"
grep -Fq '[ -x "${ZIG_HOST_LD}" ]' "$ANDROID_WORKFLOW"
grep -Fq '"${ZIG_HOST_LD}" --version >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq '"${ZIG_HOST_LD}" --help >/dev/null' "$ANDROID_WORKFLOW"
grep -Fq 'PYSTACHE_WHEEL_URL: https://files.pythonhosted.org/packages/fa/78/ffd13a516219129cef6a754a11ba2a1c0d69f1e281af4f6bca9ed5327219/pystache-0.6.8-py3-none-any.whl' "$ANDROID_WORKFLOW"
grep -Fq 'PYSTACHE_WHEEL_SHA256: 7211e000974a6e06bce2d4d5cad8df03bcfffefd367209117376e4527a1c3cb8' "$ANDROID_WORKFLOW"
grep -Fq 'SIX_WHEEL_URL: https://files.pythonhosted.org/packages/b7/ce/149a00dd41f10bc29e5921b496af8b574d8413afcd5e30dfa0ed46c2cc5e/six-1.17.0-py2.py3-none-any.whl' "$ANDROID_WORKFLOW"
grep -Fq 'SIX_WHEEL_SHA256: 4721f391ed90541fddacab5acf947aa0d3dc7d27b2e1e8eda2be8970586c3274' "$ANDROID_WORKFLOW"
grep -Fq 'MESON_WHEEL_URL: https://files.pythonhosted.org/packages/55/a6/47b9353c331318a13eb050887eacfd61eb075746285f9baf7ef7de6ae235/meson-1.5.2-py3-none-any.whl' "$ANDROID_WORKFLOW"
grep -Fq 'MESON_WHEEL_SHA256: 77706e2368a00d789c097632ccf4fc39251fba56d03e1e1b262559a3c7a08f5b' "$ANDROID_WORKFLOW"
grep -Fq 'python_site="${RUNNER_TEMP}/python-site"' "$ANDROID_WORKFLOW"
grep -Fq 'meson_wheel="${RUNNER_TEMP}/meson-1.5.2-py3-none-any.whl"' "$ANDROID_WORKFLOW"
grep -Fq 'meson_bin="${RUNNER_TEMP}/meson-bin"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "PYTHONPATH=${PYTHONPATH}" >> "${GITHUB_ENV}"' "$ANDROID_WORKFLOW"
grep -Fq 'sha256sum --check' "$ANDROID_WORKFLOW"
grep -Fq 'unzip -q "${pystache_wheel}" -d "${python_site}"' "$ANDROID_WORKFLOW"
grep -Fq 'unzip -q "${six_wheel}" -d "${python_site}"' "$ANDROID_WORKFLOW"
grep -Fq 'unzip -q "${meson_wheel}" -d "${python_site}"' "$ANDROID_WORKFLOW"
grep -Fq 'exec python3 -m mesonbuild.mesonmain "$@"' "$ANDROID_WORKFLOW"
grep -Fq 'chmod 0755 "${meson_bin}/meson"' "$ANDROID_WORKFLOW"
grep -Fq 'echo "${meson_bin}" >> "${GITHUB_PATH}"' "$ANDROID_WORKFLOW"
grep -Fq 'meson_version="$("${meson_bin}/meson" --version)"' "$ANDROID_WORKFLOW"
grep -Fq '[ "${meson_version}" = '\''1.5.2'\'' ]' "$ANDROID_WORKFLOW"
! grep -Eq 'python3[[:space:]]+-m[[:space:]]+venv|(^|[^[:alnum:]_])pip([^[:alnum:]_]|$)' "$ANDROID_WORKFLOW"

# The Android release script and workflow only extract ZIP archives; the
# runner must not require the external zip CLI for an unused preflight check.
grep -Fq 'for cmd in cmake curl doxygen git java javac make meson ninja perl python3 shasum sha256sum tar unzip; do' "$ANDROID_WORKFLOW"
! grep -Fq ' xz' "$ANDROID_WORKFLOW"
! grep -Fq 'tar -tJf' "$ANDROID_WORKFLOW"
! grep -Fq 'tar -xJf' "$ANDROID_WORKFLOW"
! grep -Fq 'for cmd in cmake curl git java javac ninja python3 shasum unzip zip; do' "$ANDROID_WORKFLOW"
! grep -Eq '(^|[^[:alnum:]_])zip([[:space:]]|$)' "${REPO_ROOT}/scripts/android-release-publish.sh"

# Job limiting is validated before any build work, propagated to nested CMake
# invocations, and passed explicitly to the top-level build. Use a mock CMake
# so these contract checks never compile the SDK.
BUILD_PROBE_ROOT="${TEST_ROOT}/build-probe"
mkdir -p "${BUILD_PROBE_ROOT}/bin"
cat > "${BUILD_PROBE_ROOT}/bin/cmake" <<'SH'
#!/usr/bin/env bash
printf 'env_jobs=%s args=' "${CMAKE_BUILD_PARALLEL_LEVEL:-unset}" >> "${PROBE_LOG}"
printf ' %q' "$@" >> "${PROBE_LOG}"
printf '\n' >> "${PROBE_LOG}"
SH
chmod +x "${BUILD_PROBE_ROOT}/bin/cmake"
PROBE_LOG="${BUILD_PROBE_ROOT}/calls.log"
set +e
PATH="${BUILD_PROBE_ROOT}/bin:${PATH}" \
  ANDROID_NDK_HOME="${TEST_ROOT}/ndk" \
  PROBE_LOG="$PROBE_LOG" \
  env -u LINPHONE_ANDROID_BUILD_JOBS bash "${REPO_ROOT}/scripts/android-release-publish.sh" \
    --build-only --build-dir "${BUILD_PROBE_ROOT}/default" --staging-dir "${BUILD_PROBE_ROOT}/staging" \
    > "${BUILD_PROBE_ROOT}/default.out" 2>&1
probe_status=$?
set -e
[ "$probe_status" -ne 0 ]
grep -Fq 'env_jobs=2' "$PROBE_LOG"
grep -Fq -- '--build ' "$PROBE_LOG"
grep -Fq -- '--parallel 2' "$PROBE_LOG"
for disabled_flag in \
  ENABLE_GPL_THIRD_PARTIES ENABLE_NON_FREE_FEATURES ENABLE_VIDEO ENABLE_ADVANCED_IM \
  ENABLE_DB_STORAGE ENABLE_VCARD ENABLE_MKV ENABLE_LDAP ENABLE_JPEG ENABLE_QRCODE \
  ENABLE_FLEXIAPI ENABLE_LIME ENABLE_LIME_X3DH ENABLE_GSM ENABLE_AV1 ENABLE_VPX \
  ENABLE_LIBYUV ENABLE_CAMERA2 ENABLE_DOC; do
  grep -Fq -- "-D${disabled_flag}=OFF" "$PROBE_LOG"
done
for enabled_flag in ENABLE_AAUDIO ENABLE_OPENSLES ENABLE_WEBRTC_AEC; do
  grep -Fq -- "-D${enabled_flag}=ON" "$PROBE_LOG"
done
: > "$PROBE_LOG"
set +e
PATH="${BUILD_PROBE_ROOT}/bin:${PATH}" \
  ANDROID_NDK_HOME="${TEST_ROOT}/ndk" \
  LINPHONE_ANDROID_BUILD_JOBS=3 \
  PROBE_LOG="$PROBE_LOG" \
  bash "${REPO_ROOT}/scripts/android-release-publish.sh" \
    --build-only --build-dir "${BUILD_PROBE_ROOT}/override" --staging-dir "${BUILD_PROBE_ROOT}/staging" \
    > "${BUILD_PROBE_ROOT}/override.out" 2>&1
probe_status=$?
set -e
[ "$probe_status" -ne 0 ]
grep -Fq 'env_jobs=3' "$PROBE_LOG"
grep -Fq -- '--parallel 3' "$PROBE_LOG"
for invalid_jobs in 0 -1 1.5 bad; do
  set +e
  LINPHONE_ANDROID_BUILD_JOBS="$invalid_jobs" bash "${REPO_ROOT}/scripts/android-release-publish.sh" \
    > "${BUILD_PROBE_ROOT}/invalid.out" 2>&1
  probe_status=$?
  set -e
  [ "$probe_status" -ne 0 ]
  grep -Fq 'LINPHONE_ANDROID_BUILD_JOBS must be a positive integer' "${BUILD_PROBE_ROOT}/invalid.out"
done

# Exercise the same source-bundle restore path used by the release workflows.
# The fixture has a real gitlink and a checked-out git repository in the archive,
# so this catches manifest, commit, and destination-restoration regressions.
SOURCE_REPO="${TEST_ROOT}/source-repo"
SOURCE_CHECKOUT="${TEST_ROOT}/source-checkout"
SOURCE_BUNDLE_ROOT="${TEST_ROOT}/source-bundle-root"
SOURCE_BUNDLE="${TEST_ROOT}/source-dependencies.tar.gz"
mkdir -p "$SOURCE_REPO" "$SOURCE_BUNDLE_ROOT"
git -C "$SOURCE_REPO" init -q
git -C "$SOURCE_REPO" config user.email test@example.invalid
git -C "$SOURCE_REPO" config user.name 'Release test'
printf 'fixture dependency\n' > "${SOURCE_REPO}/dependency.txt"
git -C "$SOURCE_REPO" add dependency.txt
git -C "$SOURCE_REPO" commit -q -m 'fixture dependency'
SOURCE_COMMIT="$(git -C "$SOURCE_REPO" rev-parse HEAD)"
git clone -q "$SOURCE_REPO" "$SOURCE_CHECKOUT"
git -C "$SOURCE_CHECKOUT" config user.email test@example.invalid
git -C "$SOURCE_CHECKOUT" config user.name 'Release test'
git -C "$SOURCE_CHECKOUT" update-index --add --cacheinfo "160000,${SOURCE_COMMIT},external/fixture"
mkdir -p "${SOURCE_BUNDLE_ROOT}/external"
cp -R "$SOURCE_REPO" "${SOURCE_BUNDLE_ROOT}/external/fixture"
printf '%s external/fixture\n' "$SOURCE_COMMIT" > "${SOURCE_BUNDLE_ROOT}/.linphone-submodules.manifest"
tar -czf "$SOURCE_BUNDLE" -C "$SOURCE_BUNDLE_ROOT" .
REPO_ROOT="$SOURCE_CHECKOUT" bash "${REPO_ROOT}/scripts/restore-submodule-source-bundle.sh" "$SOURCE_BUNDLE"
[ "$(git -C "$SOURCE_CHECKOUT/external/fixture" rev-parse HEAD)" = "$SOURCE_COMMIT" ]
[ "$(cat "$SOURCE_CHECKOUT/external/fixture/dependency.txt")" = 'fixture dependency' ]

for artifact_id in "${ARTIFACT_IDS[@]}"; do
  dir="${BUILD_DIR}/maven_repository/org/linphone/${artifact_id}/${VERSION}"
  mkdir -p "$dir"
  fixture="${TEST_ROOT}/${artifact_id}"
  for abi in arm64-v8a armeabi-v7a x86 x86_64; do mkdir -p "${fixture}/jni/${abi}"; printf x > "${fixture}/jni/${abi}/liblinphone.so"; done
  (cd "$fixture" && zip -rq "${dir}/${artifact_id}-${VERSION}.aar" .)
  rm -rf "$fixture"
  cat > "${dir}/${artifact_id}-${VERSION}.pom" <<EOF
<project><groupId>org.linphone</groupId><artifactId>${artifact_id}</artifactId><version>${VERSION}</version></project>
EOF
  printf sources > "${dir}/${artifact_id}-${VERSION}-sources.jar"
  printf javadoc > "${dir}/${artifact_id}-${VERSION}-javadoc.jar"
  printf symbols > "${dir}/${artifact_id}-${VERSION}-libs-debug.zip"
done

# The AAR guard must reject video/camera codec JNI names while accepting the
# shipped core libraries and every supported ABI.
BAD_AAR="${BUILD_DIR}/maven_repository/org/linphone/${ARTIFACT_IDS[0]}/${VERSION}/${ARTIFACT_IDS[0]}-${VERSION}.aar"
BAD_FIXTURE="${TEST_ROOT}/bad-aar"
mkdir -p "${BAD_FIXTURE}/jni/arm64-v8a"
printf x > "${BAD_FIXTURE}/jni/arm64-v8a/libvideo.so"
(cd "${BAD_FIXTURE}" && zip -q "${BAD_AAR}" jni/arm64-v8a/libvideo.so)
set +e
bash "${REPO_ROOT}/scripts/android-release-publish.sh" --build-only --skip-build \
  --build-dir "$BUILD_DIR" --staging-dir "$STAGING_DIR" \
  > "${TEST_ROOT}/bad-aar.out" 2>&1
bad_aar_status=$?
set -e
[ "$bad_aar_status" -ne 0 ]
grep -Fq 'contains unexpected video JNI artifacts' "${TEST_ROOT}/bad-aar.out"
zip -dq "${BAD_AAR}" jni/arm64-v8a/libvideo.so
rm -rf "$BAD_FIXTURE"

cat > "${TEST_ROOT}/server.py" <<'PY'
import http.server, os, socketserver, sys
root, port_file = sys.argv[1:]
class Handler(http.server.BaseHTTPRequestHandler):
    def path_on_disk(self): return os.path.join(root, self.path.lstrip('/'))
    def do_HEAD(self):
        self.send_response(200 if os.path.exists(self.path_on_disk()) else 404); self.end_headers()
    def do_GET(self):
        path = self.path_on_disk()
        if not os.path.exists(path): self.send_response(404); self.end_headers(); return
        self.send_response(200); self.send_header('Content-Length', str(os.path.getsize(path))); self.end_headers()
        with open(path, 'rb') as handle: self.wfile.write(handle.read())
    def do_PUT(self):
        path = self.path_on_disk()
        if self.headers.get('If-None-Match') != '*': self.send_response(428); self.end_headers(); return
        if os.path.exists(path): self.send_response(412); self.end_headers(); return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as handle: handle.write(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        self.send_response(201); self.end_headers()
    def log_message(self, *_): pass
with socketserver.TCPServer(('127.0.0.1', 0), Handler) as server:
    with open(port_file, 'w') as handle: handle.write(str(server.server_address[1]))
    server.serve_forever()
PY
python3 "${TEST_ROOT}/server.py" "$REMOTE_DIR" "$PORT_FILE" & SERVER_PID=$!
for _ in $(seq 1 50); do [ -f "$PORT_FILE" ] && break; sleep 0.1; done
BASE_URL="http://127.0.0.1:$(cat "$PORT_FILE")"

bash "${REPO_ROOT}/scripts/android-release-publish.sh" --build-only --skip-build --build-dir "$BUILD_DIR" --staging-dir "$STAGING_DIR" --nexus-base-url "$BASE_URL"
[ "$(find "$STAGING_DIR/maven" -type f | wc -l | tr -d ' ')" = 10 ]
bash "${REPO_ROOT}/scripts/android-release-publish.sh" --publish-staged --dry-run --staging-dir "$STAGING_DIR" --nexus-base-url "$BASE_URL" --nexus-username user --nexus-password pass
[ "$(find "$REMOTE_DIR" -type f | wc -l | tr -d ' ')" = 0 ]
bash "${REPO_ROOT}/scripts/android-release-publish.sh" --publish-staged --staging-dir "$STAGING_DIR" --nexus-base-url "$BASE_URL" --nexus-username user --nexus-password pass
[ "$(find "$REMOTE_DIR" -type f | wc -l | tr -d ' ')" = 10 ]
set +e
bash "${REPO_ROOT}/scripts/android-release-publish.sh" --publish-staged --dry-run --staging-dir "$STAGING_DIR" --nexus-base-url "$BASE_URL" --nexus-username user --nexus-password pass
status=$?
set -e
[ "$status" -ne 0 ] || { echo 'expected overwrite refusal' >&2; exit 1; }
echo 'android release publish fixture test passed'
