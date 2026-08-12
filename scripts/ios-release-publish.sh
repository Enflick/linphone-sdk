#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build-ios-release}"
STAGING_DIR="${STAGING_DIR:-${REPO_ROOT}/out/ios-release}"
CMAKE_PRESET="${CMAKE_PRESET:-ios-sdk}"
CMAKE_CONFIG="${CMAKE_CONFIG:-RelWithDebInfo}"
IOS_ARCHS="${IOS_ARCHS:-arm64,x86_64}"
IOS_PLATFORM="${IOS_PLATFORM:-Both}"
ENABLE_VIDEO="${ENABLE_VIDEO:-ON}"
NEXUS_BASE_URL="${NEXUS_BASE_URL:-https://nexus.tools.textnow.io}"
NEXUS_REPOSITORY="${NEXUS_REPOSITORY:-ios-release}"
NEXUS_USERNAME="${NEXUS_USERNAME:-${NEXUS_CAPI_USER:-}}"
NEXUS_PASSWORD="${NEXUS_PASSWORD:-${NEXUS_CAPI_PASSWORD:-}}"
OTOOL_BIN="${OTOOL_BIN:-otool}"

DRY_RUN=false
BUILD_ONLY=false
SKIP_BUILD=false
PUBLISH_STAGED=false

SWIFT_PACKAGE_NAME="linphone-sdk-swift-ios"

declare -a EXTRA_CMAKE_ARGS=()
declare -a UPLOAD_FILES=()
declare -a TARGET_NAMES=()
declare -a RUNTIME_DEPENDENCY_EDGES=()
RUNTIME_DEPENDENCY_COUNT=0

log() {
  printf '[ios-release] %s\n' "$*" >&2
}

die() {
  printf '[ios-release] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/ios-release-publish.sh [options]

Build the canonical iOS linphone-sdk XCFramework set, stage immutable Nexus
payloads, generate a source-only SwiftPM bundle artifact, and optionally
publish and verify the XCFramework ZIPs.

Options:
  --build-dir PATH            Build directory (default: build-ios-release)
  --staging-dir PATH          Staging/output directory (default: out/ios-release)
  --cmake-preset NAME         CMake preset (default: ios-sdk)
  --cmake-config NAME         CMake configuration (default: RelWithDebInfo)
  --ios-archs LIST            Architectures (default: arm64,x86_64)
  --ios-platform NAME         Iphone, Simulator, or Both (default: Both)
  --enable-video ON|OFF       Build video-enabled SDK (default: ON)
  --cmake-extra-arg ARG       Extra CMake configure arg (repeatable)
  --nexus-base-url URL        Nexus host base URL (default: https://nexus.tools.textnow.io)
  --nexus-repository NAME     Nexus raw repository (default: ios-release)
  --nexus-username USER       Nexus username
  --nexus-password PASS       Nexus password
  --dry-run                   Stage payloads and verify Nexus URLs are empty
  --build-only                Build and stage payloads without Nexus access
  --publish-staged            Publish a previously staged bundle from --staging-dir
  --skip-build                Reuse an existing build directory
  --help                      Show this help
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found on PATH"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

cache_value() {
  local key="$1"
  local cache_file="${BUILD_DIR}/CMakeCache.txt"
  [ -f "$cache_file" ] || die "missing CMake cache at ${cache_file}"
  sed -n "s/^${key}:.*=//p" "$cache_file" | tail -n 1
}

real_path() {
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

safe_reset_dir() {
  local dir="$1"
  local resolved=""

  mkdir -p "$dir"
  resolved="$(real_path "$dir")"
  case "$resolved" in
    "${REPO_ROOT}"/out/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*)
      ;;
    *)
      die "refusing to clear unsafe staging path ${resolved}"
      ;;
  esac

  [ "$resolved" != "/" ] || die "refusing to clear root directory"
  rm -rf "$resolved"
  mkdir -p "$resolved"
}

remote_url_for() {
  printf '%s/%s' "${RELEASE_ROOT_URL}" "$1"
}

head_status() {
  local url="$1"
  if [ -n "$NEXUS_USERNAME" ] || [ -n "$NEXUS_PASSWORD" ]; then
    curl \
      --silent \
      --show-error \
      --connect-timeout 10 \
      --max-time 60 \
      --output /dev/null \
      --write-out '%{http_code}' \
      --head \
      --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
      "$url" || true
  else
    curl \
      --silent \
      --show-error \
      --connect-timeout 10 \
      --max-time 60 \
      --output /dev/null \
      --write-out '%{http_code}' \
      --head \
      "$url" || true
  fi
}

assert_release_root_missing() {
  local status
  local url

  url="${RELEASE_ROOT_URL%/}/"
  status="$(head_status "$url")"
  case "$status" in
    404)
      ;;
    200|204|301|302|307|308)
      die "refusing to publish into existing Nexus release ${url}"
      ;;
    000)
      die "failed to reach Nexus while checking ${url}"
      ;;
    *)
      die "unexpected HTTP ${status} while checking ${url}"
      ;;
  esac
}

upload_file() {
  local rel_path="$1"
  local file="${NEXUS_STAGE_DIR}/${rel_path}"
  local url

  url="$(remote_url_for "$rel_path")"
  if [ -n "$NEXUS_USERNAME" ] || [ -n "$NEXUS_PASSWORD" ]; then
    curl --fail --silent --show-error \
      --connect-timeout 10 \
      --max-time 120 \
      --header 'If-None-Match: *' \
      --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" \
      --upload-file "$file" \
      "$url"
  else
    curl --fail --silent --show-error \
      --connect-timeout 10 \
      --max-time 120 \
      --header 'If-None-Match: *' \
      --upload-file "$file" \
      "$url"
  fi
}

verify_download() {
  local rel_path="$1"
  local staged_file="${NEXUS_STAGE_DIR}/${rel_path}"
  local downloaded_file="${VERIFY_DIR}/${rel_path}"
  local url

  mkdir -p "$(dirname "$downloaded_file")"
  url="$(remote_url_for "$rel_path")"
  if [ -n "$NEXUS_USERNAME" ] || [ -n "$NEXUS_PASSWORD" ]; then
    curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
      --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" --output "$downloaded_file" "$url"
  else
    curl --fail --silent --show-error --connect-timeout 10 --max-time 120 \
      --output "$downloaded_file" "$url"
  fi

  if [[ "$rel_path" == *.sha256 ]]; then
    cmp -s "$staged_file" "$downloaded_file" || die "downloaded sidecar mismatch for ${rel_path}"
    return
  fi

  [ "$(sha256_file "$staged_file")" = "$(sha256_file "$downloaded_file")" ] \
    || die "downloaded checksum mismatch for ${rel_path}"
}

write_sidecar() {
  local file="$1"
  printf '%s  %s\n' "$(sha256_file "$file")" "$(basename "$file")" > "${file}.sha256"
}

is_test_only_target_name() {
  local candidate=""
  candidate="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$candidate" in
    *tester)
      return 0
      ;;
  esac
  return 1
}

load_target_names_from_generated_package() {
  local package_file="${SWIFT_PACKAGE_DIR}/Package.swift"
  local target=""
  local raw_target_count=0
  local zip_count=""
  local selected_zip_count=0

  [ -f "${package_file}" ] || die "missing generated Swift package manifest ${package_file}"
  TARGET_NAMES=()
  while IFS= read -r target; do
    [ -n "${target}" ] || continue
    raw_target_count=$((raw_target_count + 1))
    if is_test_only_target_name "${target}"; then
      continue
    fi
    TARGET_NAMES+=("${target}")
  done < <(python3 - "${package_file}" <<'PY'
import re
import sys

content = open(sys.argv[1], "r", encoding="utf-8").read()
for name in re.findall(r'\.binaryTarget\(\s*name:\s*"([^"]+)"', content, re.S):
    print(name)
PY
)

  [ "${raw_target_count}" -gt 0 ] || die "no binary targets found in ${package_file}"
  [ "${#TARGET_NAMES[@]}" -gt 0 ] || die "no production binary targets remain in ${package_file} after excluding test-only frameworks"
  zip_count="$(find "${XCFRAMEWORK_DIR}" -maxdepth 1 -type f -name '*.xcframework.zip' | wc -l | tr -d ' ')"
  for target in "${TARGET_NAMES[@]}"; do
    [ -f "${XCFRAMEWORK_DIR}/${target}.xcframework.zip" ] || die "missing expected artifact ${XCFRAMEWORK_DIR}/${target}.xcframework.zip"
    selected_zip_count=$((selected_zip_count + 1))
  done
  [ "${zip_count}" -ge "${selected_zip_count}" ] \
    || die "generated Swift package selects ${selected_zip_count} production targets but only ${zip_count} XCFramework ZIPs were built"
}

target_exists() {
  local candidate="$1"
  local target=""
  for target in "${TARGET_NAMES[@]}"; do
    [ "$target" = "$candidate" ] && return 0
  done
  return 1
}

find_raw_xcframework_dir() {
  local matches=()

  if [ -d "${BUILD_DIR}/linphone-sdk/apple-darwin/XCFrameworks" ]; then
    printf '%s\n' "${BUILD_DIR}/linphone-sdk/apple-darwin/XCFrameworks"
    return
  fi
  if [ -d "${BUILD_DIR}/linphone-sdk-novideo/apple-darwin/XCFrameworks" ]; then
    printf '%s\n' "${BUILD_DIR}/linphone-sdk-novideo/apple-darwin/XCFrameworks"
    return
  fi

  while IFS= read -r match; do
    [ -n "$match" ] || continue
    matches+=("$match")
  done < <(find "${BUILD_DIR}" -type d -path '*/apple-darwin/XCFrameworks' | sort)

  [ "${#matches[@]}" -gt 0 ] || die "could not find raw XCFramework directory under ${BUILD_DIR}"
  [ "${#matches[@]}" -eq 1 ] || die "found multiple raw XCFramework directories under ${BUILD_DIR}: ${matches[*]}"
  printf '%s\n' "${matches[0]}"
}

collect_runtime_dependencies_for_binary() {
  local binary_path="$1"
  "${OTOOL_BIN}" -L "${binary_path}" | python3 -c '
import re
import sys

pattern = re.compile(r"^\s+@rpath/([^/\s]+)\.framework/\1(?:\s|$)")
for line in sys.stdin:
    match = pattern.match(line)
    if match:
        print(match.group(1))
'
}

verify_runtime_dependency_closure() {
  local raw_xcframework_dir=""
  local target=""
  local framework_dir=""
  local framework_name=""
  local slice=""
  local binary_path=""
  local dependency=""

  if ! command -v "${OTOOL_BIN}" >/dev/null 2>&1 && [ ! -x "${OTOOL_BIN}" ]; then
    die "required otool command '${OTOOL_BIN}' not found for runtime dependency validation"
  fi

  raw_xcframework_dir="$(find_raw_xcframework_dir)"
  RUNTIME_DEPENDENCY_EDGES=()
  RUNTIME_DEPENDENCY_COUNT=0

  for target in "${TARGET_NAMES[@]}"; do
    framework_dir="${raw_xcframework_dir}/${target}.xcframework"
    framework_name="${target}"
    [ -d "${framework_dir}" ] || die "missing raw XCFramework directory ${framework_dir}"
    for slice in ios-arm64 ios-arm64_x86_64-simulator; do
      binary_path="${framework_dir}/${slice}/${framework_name}.framework/${framework_name}"
      [ -f "${binary_path}" ] || die "missing framework binary ${binary_path}"
      while IFS= read -r dependency; do
        [ -n "${dependency}" ] || continue
        target_exists "${dependency}" \
          || die "runtime dependency closure failure: ${target} (${slice}) references ${dependency}, which is not packaged"
        RUNTIME_DEPENDENCY_EDGES+=("${target}|${slice}|${dependency}")
        RUNTIME_DEPENDENCY_COUNT=$((RUNTIME_DEPENDENCY_COUNT + 1))
      done < <(collect_runtime_dependencies_for_binary "${binary_path}")
    done
  done
}

copy_nexus_file() {
  local src="$1"
  local name="$2"
  cp "$src" "${NEXUS_STAGE_DIR}/${name}"
  write_sidecar "${NEXUS_STAGE_DIR}/${name}"
  UPLOAD_FILES+=("${name}" "${name}.sha256")
}

configure_build() {
  local -a cmd=(
    cmake
    "--preset=${CMAKE_PRESET}"
    -B "${BUILD_DIR}"
    "-DCMAKE_BUILD_TYPE=${CMAKE_CONFIG}"
    "-DLINPHONESDK_IOS_PLATFORM=${IOS_PLATFORM}"
    "-DLINPHONESDK_IOS_ARCHS=${IOS_ARCHS}"
    "-DENABLE_FAT_BINARY=OFF"
    "-DENABLE_SWIFT_WRAPPER=ON"
    "-DUPLOAD_SWIFT_PACKAGE=ON"
    "-DLINPHONESDK_IOS_BASE_URL=https://invalid.example/LinphoneSDK"
  )

  if [ "$ENABLE_VIDEO" = "OFF" ]; then
    cmd+=("-DENABLE_VIDEO=OFF")
  fi

  if [ "${#EXTRA_CMAKE_ARGS[@]}" -gt 0 ]; then
    cmd+=("${EXTRA_CMAKE_ARGS[@]}")
  fi

  log "configuring ${BUILD_DIR}"
  "${cmd[@]}"
}

build_if_needed() {
  if $SKIP_BUILD; then
    log "reusing existing build at ${BUILD_DIR}"
    return
  fi

  configure_build
  log "building iOS SDK"
  cmake --build "${BUILD_DIR}" --config "${CMAKE_CONFIG}" --parallel
}

load_release_context() {
  local source_sha_input=""

  SDK_VERSION="$(cache_value LINPHONESDK_VERSION_CACHED)"
  SDK_VERSION_BASE="${SDK_VERSION%%+*}"
  [ -n "$SDK_VERSION_BASE" ] || die "failed to derive base SDK version from ${SDK_VERSION}"

  source_sha_input="${GITHUB_SHA:-}"
  if [ -n "${source_sha_input}" ]; then
    SOURCE_COMMIT="${source_sha_input}"
    SOURCE_SHORT_SHA="${source_sha_input:0:9}"
  else
    SOURCE_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
    SOURCE_SHORT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short=9 HEAD)"
  fi
  RELEASE_VERSION="${SDK_VERSION_BASE}-${SOURCE_SHORT_SHA}"
  RELEASE_ROOT_URL="${NEXUS_BASE_URL%/}/repository/${NEXUS_REPOSITORY}/LinphoneSDK/${RELEASE_VERSION}"
  SWIFT_PACKAGE_DIR="${BUILD_DIR}/${SWIFT_PACKAGE_NAME}"
  XCFRAMEWORK_DIR="${SWIFT_PACKAGE_DIR}/XCFrameworks"
}

verify_xcframework_zip() {
  local zip_file="$1"
  local bundle_name
  local framework_name
  local entries
  local debug_symbol_library_count

  bundle_name="$(basename "$zip_file" .zip)"
  framework_name="${bundle_name%.xcframework}"
  entries="$(unzip -Z1 "$zip_file")"
  printf '%s\n' "$entries" | grep -q "^${bundle_name}/ios-arm64/" \
    || die "${zip_file} is missing ios-arm64"
  printf '%s\n' "$entries" | grep -q "^${bundle_name}/ios-arm64_x86_64-simulator/" \
    || die "${zip_file} is missing ios-arm64_x86_64-simulator"
  printf '%s\n' "$entries" | grep -q "^${bundle_name}/ios-arm64/dSYMs/${framework_name}\.framework\.dSYM/Contents/Resources/DWARF/${framework_name}$" \
    || die "${zip_file} is missing the ios-arm64 dSYM DWARF binary"
  printf '%s\n' "$entries" | grep -q "^${bundle_name}/ios-arm64_x86_64-simulator/dSYMs/${framework_name}\.framework\.dSYM/Contents/Resources/DWARF/${framework_name}$" \
    || die "${zip_file} is missing the simulator dSYM DWARF binary"
  debug_symbol_library_count="$(python3 - "$zip_file" "${bundle_name}/Info.plist" <<'PY'
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    plist = plistlib.loads(archive.read(sys.argv[2]))
libraries = plist.get("AvailableLibraries", [])
print(sum(library.get("DebugSymbolsPath") == "dSYMs" for library in libraries))
PY
)"
  [ "$debug_symbol_library_count" -eq 2 ] \
    || die "${zip_file} does not declare dSYMs for both XCFramework slices"
}

verify_generated_targets() {
  local zip_files=("${XCFRAMEWORK_DIR}"/*.zip)
  local target=""
  local zip_file=""

  [ -d "$SWIFT_PACKAGE_DIR" ] || die "missing SwiftPM output ${SWIFT_PACKAGE_DIR}"
  [ -d "$XCFRAMEWORK_DIR" ] || die "missing XCFramework directory ${XCFRAMEWORK_DIR}"
  [ "${#zip_files[@]}" -gt 0 ] || die "expected at least one XCFramework ZIP in ${XCFRAMEWORK_DIR}"
  load_target_names_from_generated_package
  verify_runtime_dependency_closure

  for target in "${TARGET_NAMES[@]}"; do
    zip_file="${XCFRAMEWORK_DIR}/${target}.xcframework.zip"
    [ -f "$zip_file" ] || die "missing expected artifact ${zip_file}"
    verify_xcframework_zip "$zip_file"
  done
}

write_source_package() {
  local package_file="${SOURCE_BUNDLE_DIR}/Package.swift"
  local target=""
  local zip_name=""
  local checksum=""

  {
    cat <<'EOF'
// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "linphonesw",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "linphonesw",
            targets: ["linphonesw"]
        )
    ],
    targets: [
EOF
    for target in "${TARGET_NAMES[@]}"; do
      zip_name="${target}.xcframework.zip"
      checksum="$(sha256_file "${XCFRAMEWORK_DIR}/${zip_name}")"
      cat <<EOF
        .binaryTarget(
            name: "${target}",
            url: "${RELEASE_ROOT_URL}/${zip_name}",
            checksum: "${checksum}"
        ),
EOF
    done
    printf '        .target(\n'
    printf '            name: "linphonesw",\n'
    printf '            dependencies: ['
    local first=true
    for target in "${TARGET_NAMES[@]}"; do
      if $first; then
        first=false
      else
        printf ', '
      fi
      printf '"%s"' "$target"
    done
    cat <<'EOF'
]
        )
    ]
)
EOF
  } > "$package_file"
}

stage_source_bundle() {
  local file=""
  local rel_name=""

  mkdir -p "${SOURCE_BUNDLE_DIR}/Sources"

  for rel_name in LICENSE.txt README.md VERSION; do
    file="${SWIFT_PACKAGE_DIR}/${rel_name}"
    [ -f "$file" ] && cp "$file" "${SOURCE_BUNDLE_DIR}/${rel_name}"
  done

  cp -R "${SWIFT_PACKAGE_DIR}/Sources/linphonesw" "${SOURCE_BUNDLE_DIR}/Sources/"
  printf '%s\n' "${SOURCE_COMMIT}" > "${SOURCE_BUNDLE_DIR}/SOURCE-COMMIT"
  printf '%s\n' "${RELEASE_ROOT_URL}" > "${SOURCE_BUNDLE_DIR}/NEXUS-RELEASE-ROOT"
  write_source_package

  SOURCE_BUNDLE_ZIP="linphone-sdk-swift-ios-source-${RELEASE_VERSION}.zip"
  (
    cd "${SOURCE_ARTIFACT_ROOT}"
    zip -rq "../${SOURCE_BUNDLE_ZIP}" "${SWIFT_PACKAGE_NAME}"
  )
}

manifest_value() {
  local key="$1"
  local manifest_file="$2"
  sed -n "s/^${key}=//p" "$manifest_file" | tail -n 1
}

write_manifest() {
  local manifest_file="${STAGING_DIR}/release-manifest.txt"
  local runtime_edge=""
  local target=""
  local zip_name=""

  {
    printf 'sdk_version=%s\n' "${SDK_VERSION}"
    printf 'sdk_version_base=%s\n' "${SDK_VERSION_BASE}"
    printf 'source_commit=%s\n' "${SOURCE_COMMIT}"
    printf 'source_short_sha=%s\n' "${SOURCE_SHORT_SHA}"
    printf 'release_version=%s\n' "${RELEASE_VERSION}"
    printf 'release_root_url=%s\n' "${RELEASE_ROOT_URL}"
    printf 'mode=%s\n' "${RUN_MODE}"
    printf 'target_count=%s\n' "${#TARGET_NAMES[@]}"
    printf 'runtime_dependency_count=%s\n' "${RUNTIME_DEPENDENCY_COUNT}"
    printf '\n'
    printf '# runtime dependency closure\n'
    if [ "${RUNTIME_DEPENDENCY_COUNT}" -gt 0 ]; then
      for runtime_edge in "${RUNTIME_DEPENDENCY_EDGES[@]}"; do
        printf 'runtime_dependency=%s\n' "${runtime_edge}"
      done
    fi
    printf '\n'
    printf '# nexus payload\n'
    for target in "${TARGET_NAMES[@]}"; do
      zip_name="${target}.xcframework.zip"
      printf 'target=%s\n' "${target}"
      printf '%s %s\n' "${zip_name}" "$(sha256_file "${NEXUS_STAGE_DIR}/${zip_name}")"
    done
  } > "$manifest_file"
}

stage_outputs() {
  local target=""
  local zip_name=""
  safe_reset_dir "$STAGING_DIR"

  NEXUS_STAGE_DIR="${STAGING_DIR}/nexus"
  VERIFY_DIR="${STAGING_DIR}/verified-downloads"
  SOURCE_ARTIFACT_ROOT="${STAGING_DIR}/source-bundle"
  SOURCE_BUNDLE_DIR="${SOURCE_ARTIFACT_ROOT}/${SWIFT_PACKAGE_NAME}"

  mkdir -p "$NEXUS_STAGE_DIR" "$VERIFY_DIR" "$SOURCE_BUNDLE_DIR"
  UPLOAD_FILES=()

  for target in "${TARGET_NAMES[@]}"; do
    zip_name="${target}.xcframework.zip"
    copy_nexus_file "${XCFRAMEWORK_DIR}/${zip_name}" "$zip_name"
  done

  stage_source_bundle
  write_manifest
}

load_staged_context() {
  local expected_release_root=""
  local actual_zip_count=""
  local actual_sidecar_count=""
  local manifest_target_count=""
  local manifest_runtime_dependency_count=""
  local runtime_edge=""
  local runtime_source=""
  local runtime_slice=""
  local runtime_dependency=""
  local target=""
  local zip_name=""
  local source_sha_input=""

  NEXUS_STAGE_DIR="${STAGING_DIR}/nexus"
  VERIFY_DIR="${STAGING_DIR}/verified-downloads"
  SOURCE_ARTIFACT_ROOT="${STAGING_DIR}/source-bundle"
  SOURCE_BUNDLE_DIR="${SOURCE_ARTIFACT_ROOT}/${SWIFT_PACKAGE_NAME}"
  MANIFEST_FILE="${STAGING_DIR}/release-manifest.txt"

  [ -f "${MANIFEST_FILE}" ] || die "missing staged manifest ${MANIFEST_FILE}"
  [ -d "${NEXUS_STAGE_DIR}" ] || die "missing staged Nexus payload ${NEXUS_STAGE_DIR}"

  SDK_VERSION="$(manifest_value sdk_version "${MANIFEST_FILE}")"
  SDK_VERSION_BASE="$(manifest_value sdk_version_base "${MANIFEST_FILE}")"
  SOURCE_COMMIT="$(manifest_value source_commit "${MANIFEST_FILE}")"
  SOURCE_SHORT_SHA="$(manifest_value source_short_sha "${MANIFEST_FILE}")"
  RELEASE_VERSION="$(manifest_value release_version "${MANIFEST_FILE}")"
  RELEASE_ROOT_URL="$(manifest_value release_root_url "${MANIFEST_FILE}")"
  SOURCE_BUNDLE_ZIP="linphone-sdk-swift-ios-source-${RELEASE_VERSION}.zip"

  [ -n "${SDK_VERSION_BASE}" ] || die "staged manifest missing sdk_version_base"
  [ -n "${RELEASE_VERSION}" ] || die "staged manifest missing release_version"
  [ -n "${RELEASE_ROOT_URL}" ] || die "staged manifest missing release_root_url"
  [ -f "${STAGING_DIR}/${SOURCE_BUNDLE_ZIP}" ] || die "missing staged source bundle ${SOURCE_BUNDLE_ZIP}"
  manifest_target_count="$(manifest_value target_count "${MANIFEST_FILE}")"
  [ -n "${manifest_target_count}" ] || die "staged manifest missing target_count"
  manifest_runtime_dependency_count="$(manifest_value runtime_dependency_count "${MANIFEST_FILE}")"
  [ -n "${manifest_runtime_dependency_count}" ] || die "staged manifest missing runtime_dependency_count"

  TARGET_NAMES=()
  while IFS= read -r target; do
    [ -n "${target}" ] || continue
    TARGET_NAMES+=("${target}")
  done < <(sed -n 's/^target=//p' "${MANIFEST_FILE}")
  [ "${#TARGET_NAMES[@]}" = "${manifest_target_count}" ] \
    || die "staged manifest target_count ${manifest_target_count} does not match ${#TARGET_NAMES[@]} targets"

  RUNTIME_DEPENDENCY_EDGES=()
  RUNTIME_DEPENDENCY_COUNT=0
  while IFS= read -r runtime_edge; do
    [ -n "${runtime_edge}" ] || continue
    RUNTIME_DEPENDENCY_EDGES+=("${runtime_edge}")
    RUNTIME_DEPENDENCY_COUNT=$((RUNTIME_DEPENDENCY_COUNT + 1))
  done < <(sed -n 's/^runtime_dependency=//p' "${MANIFEST_FILE}")
  [ "${RUNTIME_DEPENDENCY_COUNT}" = "${manifest_runtime_dependency_count}" ] \
    || die "staged manifest runtime_dependency_count ${manifest_runtime_dependency_count} does not match ${RUNTIME_DEPENDENCY_COUNT} runtime dependencies"
  if [ "${RUNTIME_DEPENDENCY_COUNT}" -gt 0 ]; then
    for runtime_edge in "${RUNTIME_DEPENDENCY_EDGES[@]}"; do
      runtime_source="${runtime_edge%%|*}"
      runtime_slice="${runtime_edge#*|}"
      runtime_slice="${runtime_slice%%|*}"
      runtime_dependency="${runtime_edge##*|}"
      [ "${runtime_source}" != "${runtime_edge}" ] || die "malformed runtime dependency entry ${runtime_edge}"
      [ -n "${runtime_slice}" ] || die "malformed runtime dependency entry ${runtime_edge}"
      [ "${runtime_slice}" = "ios-arm64" ] || [ "${runtime_slice}" = "ios-arm64_x86_64-simulator" ] \
        || die "unexpected runtime dependency slice ${runtime_slice}"
      target_exists "${runtime_source}" || die "runtime dependency source ${runtime_source} is not packaged"
      target_exists "${runtime_dependency}" || die "runtime dependency target ${runtime_dependency} is not packaged"
    done
  fi

  actual_zip_count="$(find "${NEXUS_STAGE_DIR}" -maxdepth 1 -type f -name '*.xcframework.zip' | wc -l | tr -d ' ')"
  actual_sidecar_count="$(find "${NEXUS_STAGE_DIR}" -maxdepth 1 -type f -name '*.xcframework.zip.sha256' | wc -l | tr -d ' ')"
  [ "${actual_zip_count}" = "${#TARGET_NAMES[@]}" ] \
    || die "expected ${#TARGET_NAMES[@]} staged XCFramework ZIPs, found ${actual_zip_count}"
  [ "${actual_sidecar_count}" = "${#TARGET_NAMES[@]}" ] \
    || die "expected ${#TARGET_NAMES[@]} staged checksum sidecars, found ${actual_sidecar_count}"

  for target in "${TARGET_NAMES[@]}"; do
    zip_name="${target}.xcframework.zip"
    [ -f "${NEXUS_STAGE_DIR}/${zip_name}" ] || die "missing staged artifact ${zip_name}"
    [ -f "${NEXUS_STAGE_DIR}/${zip_name}.sha256" ] || die "missing staged checksum sidecar ${zip_name}.sha256"
    [ "$(cat "${NEXUS_STAGE_DIR}/${zip_name}.sha256")" = "$(sha256_file "${NEXUS_STAGE_DIR}/${zip_name}")  ${zip_name}" ] \
      || die "checksum sidecar mismatch for ${zip_name}"
    verify_xcframework_zip "${NEXUS_STAGE_DIR}/${zip_name}"
  done

  source_sha_input="${GITHUB_SHA:-}"
  if [ -n "${source_sha_input}" ]; then
    source_sha_input="${source_sha_input:0:9}"
    [ "${SOURCE_SHORT_SHA}" = "${source_sha_input}" ] \
      || die "staged source short SHA ${SOURCE_SHORT_SHA} does not match GITHUB_SHA ${source_sha_input}"
    [ "${RELEASE_VERSION}" = "${SDK_VERSION_BASE}-${source_sha_input}" ] \
      || die "staged release version ${RELEASE_VERSION} does not match ${SDK_VERSION_BASE}-${source_sha_input}"
  fi

  expected_release_root="${NEXUS_BASE_URL%/}/repository/${NEXUS_REPOSITORY}/LinphoneSDK/${RELEASE_VERSION}"
  [ "${RELEASE_ROOT_URL}" = "${expected_release_root}" ] \
    || die "staged release root ${RELEASE_ROOT_URL} does not match ${expected_release_root}"

  UPLOAD_FILES=()
  for target in "${TARGET_NAMES[@]}"; do
    zip_name="${target}.xcframework.zip"
    UPLOAD_FILES+=("${zip_name}" "${zip_name}.sha256")
  done
}

require_publish_credentials() {
  [ -n "$NEXUS_USERNAME" ] || die "Nexus username is required for ${RUN_MODE}"
  [ -n "$NEXUS_PASSWORD" ] || die "Nexus password is required for ${RUN_MODE}"
}

publish_uploads() {
  local rel_path=""
  for rel_path in "${UPLOAD_FILES[@]}"; do
    upload_file "$rel_path"
  done
}

verify_uploads() {
  local rel_path=""
  for rel_path in "${UPLOAD_FILES[@]}"; do
    verify_download "$rel_path"
  done
}

emit_outputs() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      printf 'sdk_version=%s\n' "${SDK_VERSION}"
      printf 'sdk_version_base=%s\n' "${SDK_VERSION_BASE}"
      printf 'source_commit=%s\n' "${SOURCE_COMMIT}"
      printf 'source_short_sha=%s\n' "${SOURCE_SHORT_SHA}"
      printf 'release_version=%s\n' "${RELEASE_VERSION}"
      printf 'release_root_url=%s\n' "${RELEASE_ROOT_URL}"
      printf 'source_bundle_zip=%s\n' "${SOURCE_BUNDLE_ZIP}"
      printf 'staging_dir=%s\n' "${STAGING_DIR}"
    } >> "${GITHUB_OUTPUT}"
  fi

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      printf '## iOS release staging\n\n'
      printf -- '- Mode: `%s`\n' "${RUN_MODE}"
      printf -- '- SDK version: `%s`\n' "${SDK_VERSION}"
      printf -- '- Release version: `%s`\n' "${RELEASE_VERSION}"
      printf -- '- Release root: `%s`\n' "${RELEASE_ROOT_URL}"
      printf -- '- Source bundle: `%s`\n' "${SOURCE_BUNDLE_ZIP}"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --build-dir)
        BUILD_DIR="$2"
        shift 2
        ;;
      --staging-dir)
        STAGING_DIR="$2"
        shift 2
        ;;
      --cmake-preset)
        CMAKE_PRESET="$2"
        shift 2
        ;;
      --cmake-config)
        CMAKE_CONFIG="$2"
        shift 2
        ;;
      --ios-archs)
        IOS_ARCHS="$2"
        shift 2
        ;;
      --ios-platform)
        IOS_PLATFORM="$2"
        shift 2
        ;;
      --enable-video)
        ENABLE_VIDEO="$2"
        shift 2
        ;;
      --cmake-extra-arg)
        EXTRA_CMAKE_ARGS+=("$2")
        shift 2
        ;;
      --nexus-base-url)
        NEXUS_BASE_URL="$2"
        shift 2
        ;;
      --nexus-repository)
        NEXUS_REPOSITORY="$2"
        shift 2
        ;;
      --nexus-username)
        NEXUS_USERNAME="$2"
        shift 2
        ;;
      --nexus-password)
        NEXUS_PASSWORD="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --build-only)
        BUILD_ONLY=true
        shift
        ;;
      --skip-build)
        SKIP_BUILD=true
        shift
        ;;
      --publish-staged)
        PUBLISH_STAGED=true
        shift
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if $PUBLISH_STAGED && $SKIP_BUILD; then
    die "--publish-staged already implies no native build; do not combine it with --skip-build"
  fi

  if $BUILD_ONLY && $PUBLISH_STAGED; then
    die "--build-only and --publish-staged are mutually exclusive"
  fi

  if $BUILD_ONLY && $DRY_RUN; then
    die "--build-only and --dry-run are mutually exclusive"
  fi

  RUN_MODE="publish"
  if $BUILD_ONLY; then
    RUN_MODE="build-only"
  elif $PUBLISH_STAGED && $DRY_RUN; then
    RUN_MODE="publish-staged-dry-run"
  elif $PUBLISH_STAGED; then
    RUN_MODE="publish-staged"
  elif $DRY_RUN; then
    RUN_MODE="dry-run"
  fi

  require_cmd curl
  require_cmd python3
  require_cmd shasum
  require_cmd unzip
  if $PUBLISH_STAGED; then
    load_staged_context
  else
    require_cmd cmake
    require_cmd git
    require_cmd zip

    build_if_needed
    load_release_context
    verify_generated_targets
    stage_outputs
  fi

  emit_outputs

  if $BUILD_ONLY; then
    log "build-only complete; staged outputs at ${STAGING_DIR}"
    return
  fi

  require_publish_credentials
  if $DRY_RUN; then
    assert_release_root_missing
    log "dry-run complete; Nexus paths are empty under ${RELEASE_ROOT_URL}"
    return
  fi

  publish_uploads
  verify_uploads
  log "publish complete; verified downloads from ${RELEASE_ROOT_URL}"
}

main "$@"
