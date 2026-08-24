#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-${REPO_ROOT}/build/android}"
STAGING_DIR="${STAGING_DIR:-${REPO_ROOT}/out/android-release}"
ANDROID_ARCHS="${ANDROID_ARCHS:-arm64,armv7,x86,x86_64}"
LINPHONE_ANDROID_BUILD_JOBS="${LINPHONE_ANDROID_BUILD_JOBS:-2}"
NEXUS_BASE_URL="${NEXUS_BASE_URL:-https://nexus.tools.textnow.io}"
NEXUS_REPOSITORY="${NEXUS_REPOSITORY:-linphone-tn}"
NEXUS_USERNAME="${NEXUS_USERNAME:-${NEXUS_CAPI_USER:-}}"
NEXUS_PASSWORD="${NEXUS_PASSWORD:-${NEXUS_CAPI_PASSWORD:-}}"

BUILD_ONLY=false
PUBLISH_STAGED=false
DRY_RUN=false
SKIP_BUILD=false
ARTIFACT_IDS=(linphone-sdk-android linphone-sdk-android-debug)
EXPECTED_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)
UPLOAD_FILES=()

# Keep the published Android AAR aligned with the shipped 5.5.12-v2-6308ecb
# voice-only artifact. These are explicit so preset defaults cannot silently
# re-enable video or its optional dependencies.
ANDROID_RELEASE_CMAKE_FLAGS=(
  -DENABLE_GPL_THIRD_PARTIES=OFF
  -DENABLE_NON_FREE_FEATURES=OFF
  -DENABLE_VIDEO=OFF
  -DENABLE_ADVANCED_IM=OFF
  -DENABLE_DB_STORAGE=OFF
  -DENABLE_VCARD=OFF
  -DENABLE_MKV=OFF
  -DENABLE_LDAP=OFF
  -DENABLE_JPEG=OFF
  -DENABLE_QRCODE=OFF
  -DENABLE_FLEXIAPI=OFF
  -DENABLE_LIME=OFF
  -DENABLE_LIME_X3DH=OFF
  -DENABLE_GSM=OFF
  -DENABLE_AV1=OFF
  -DENABLE_VPX=OFF
  -DENABLE_LIBYUV=OFF
  -DENABLE_CAMERA2=OFF
  -DENABLE_DOC=OFF
  -DENABLE_AAUDIO=ON
  -DENABLE_OPENSLES=ON
  -DENABLE_WEBRTC_AEC=ON
)

log() { printf '[android-release] %s\n' "$*" >&2; }
die() { printf '[android-release] ERROR: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found"; }
sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
real_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
validate_build_jobs() {
  [[ "$LINPHONE_ANDROID_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] \
    || die "LINPHONE_ANDROID_BUILD_JOBS must be a positive integer"
}

usage() {
  cat <<'EOF'
Usage: scripts/android-release-publish.sh [options]

  --build-dir PATH
  --staging-dir PATH
  --android-archs LIST
  --nexus-base-url URL
  --nexus-repository NAME
  --nexus-username USER
  --nexus-password PASS
  --build-only
  --publish-staged
  --dry-run
  --skip-build
EOF
}

safe_reset_dir() {
  local resolved=""
  mkdir -p "$1"
  resolved="$(real_path "$1")"
  case "$resolved" in
    "${REPO_ROOT}"/out/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) ;;
    *) die "refusing to clear unsafe staging path ${resolved}" ;;
  esac
  [ "$resolved" != "/" ] || die "refusing to clear root"
  rm -rf "$resolved"
  mkdir -p "$resolved"
}

derive_release_context() {
  local source_sha="${GITHUB_SHA:-}"
  SDK_VERSION_BASE="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --match '[0-9]*' | sed 's/^v//')"
  printf '%s' "$SDK_VERSION_BASE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || die "invalid SDK base version ${SDK_VERSION_BASE}"
  if [ -n "$source_sha" ]; then
    SOURCE_COMMIT="$source_sha"
    SOURCE_SHORT_SHA="${source_sha:0:9}"
  else
    SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    SOURCE_SHORT_SHA="$(git -C "$REPO_ROOT" rev-parse --short=9 HEAD)"
  fi
  RELEASE_VERSION="${SDK_VERSION_BASE}-${SOURCE_SHORT_SHA}"
  RELEASE_ROOT_URL="${NEXUS_BASE_URL%/}/repository/${NEXUS_REPOSITORY}/org/linphone"
}

build_sdk() {
  if $SKIP_BUILD; then
    log "reusing existing build at ${BUILD_DIR}"
    return
  fi
  [ -n "${ANDROID_NDK_HOME:-}" ] || die "ANDROID_NDK_HOME is required"
  export CMAKE_BUILD_PARALLEL_LEVEL="$LINPHONE_ANDROID_BUILD_JOBS"
  cmake --preset=android-sdk -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DLINPHONESDK_ANDROID_ARCHS="$ANDROID_ARCHS" \
    -DLINPHONESDK_VERSION="$RELEASE_VERSION" \
    "${ANDROID_RELEASE_CMAKE_FLAGS[@]}"
  cmake --build "$BUILD_DIR" --parallel "$LINPHONE_ANDROID_BUILD_JOBS"
}

verify_aar() {
  local aar="$1" abi="" entries="" unexpected=""
  entries="$(unzip -Z1 "$aar")"
  for abi in "${EXPECTED_ABIS[@]}"; do
    printf '%s\n' "$entries" | grep -q "^jni/${abi}/" || die "${aar} is missing ABI ${abi}"
  done
  unexpected="$(printf '%s\n' "$entries" | grep -Eiq '^jni/[^/]*/[^/]*(video|camera|jpeg|zxing|vpx|aom|dav1d|yuv)[^/]*$' && printf '%s\n' "$entries" | grep -Ei '^jni/[^/]*/[^/]*(video|camera|jpeg|zxing|vpx|aom|dav1d|yuv)[^/]*$' || true)"
  [ -z "$unexpected" ] || die "${aar} contains unexpected video JNI artifacts: ${unexpected}"
}

verify_pom() {
  local pom="$1" artifact_id="$2"
  grep -Eq '<groupId>[[:space:]]*org\.linphone[[:space:]]*</groupId>' "$pom" || die "invalid groupId in ${pom}"
  grep -Eq "<artifactId>[[:space:]]*${artifact_id}[[:space:]]*</artifactId>" "$pom" || die "invalid artifactId in ${pom}"
  grep -Eq "<version>[[:space:]]*${RELEASE_VERSION}[[:space:]]*</version>" "$pom" || die "invalid version in ${pom}"
}

expected_names() {
  local artifact_id="$1"
  printf '%s\n' \
    "${artifact_id}-${RELEASE_VERSION}.aar" \
    "${artifact_id}-${RELEASE_VERSION}.pom" \
    "${artifact_id}-${RELEASE_VERSION}-sources.jar" \
    "${artifact_id}-${RELEASE_VERSION}-javadoc.jar" \
    "${artifact_id}-${RELEASE_VERSION}-libs-debug.zip"
}

validate_version_dir() {
  local root="$1" artifact_id="$2" version_dir="" name="" count=""
  version_dir="${root}/${artifact_id}/${RELEASE_VERSION}"
  [ -d "$version_dir" ] || die "missing Maven version directory ${version_dir}"
  count="$(find "$version_dir" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  [ "$count" -ge 5 ] || die "expected at least 5 immutable assets for ${artifact_id}, found ${count}"
  while IFS= read -r name; do [ -f "${version_dir}/${name}" ] || die "missing ${name}"; done < <(expected_names "$artifact_id")
  verify_aar "${version_dir}/${artifact_id}-${RELEASE_VERSION}.aar"
  verify_pom "${version_dir}/${artifact_id}-${RELEASE_VERSION}.pom" "$artifact_id"
}

write_manifest() {
  local rel=""
  {
    printf 'sdk_version_base=%s\nsource_commit=%s\nsource_short_sha=%s\nrelease_version=%s\nrelease_root_url=%s\n' \
      "$SDK_VERSION_BASE" "$SOURCE_COMMIT" "$SOURCE_SHORT_SHA" "$RELEASE_VERSION" "$RELEASE_ROOT_URL"
    printf '\n# payload\n'
    for rel in "${UPLOAD_FILES[@]}"; do printf '%s %s\n' "$rel" "$(sha256_file "${STAGING_DIR}/maven/${rel}")"; done
  } > "${STAGING_DIR}/release-manifest.txt"
}

stage_build() {
  local artifact_id="" name="" rel="" source_root="${BUILD_DIR}/maven_repository/org/linphone"
  for artifact_id in "${ARTIFACT_IDS[@]}"; do validate_version_dir "$source_root" "$artifact_id"; done
  safe_reset_dir "$STAGING_DIR"
  mkdir -p "${STAGING_DIR}/maven"
  for artifact_id in "${ARTIFACT_IDS[@]}"; do
    while IFS= read -r name; do
      rel="${artifact_id}/${RELEASE_VERSION}/${name}"
      mkdir -p "$(dirname "${STAGING_DIR}/maven/${rel}")"
      cp "${source_root}/${rel}" "${STAGING_DIR}/maven/${rel}"
      UPLOAD_FILES+=("$rel")
    done < <(expected_names "$artifact_id")
  done
  write_manifest
}

manifest_value() { sed -n "s/^$1=//p" "${STAGING_DIR}/release-manifest.txt" | tail -n 1; }

load_staged() {
  local artifact_id="" name="" rel="" expected_sha=""
  [ -f "${STAGING_DIR}/release-manifest.txt" ] || die "missing staged release manifest"
  SDK_VERSION_BASE="$(manifest_value sdk_version_base)"
  SOURCE_COMMIT="$(manifest_value source_commit)"
  SOURCE_SHORT_SHA="$(manifest_value source_short_sha)"
  RELEASE_VERSION="$(manifest_value release_version)"
  RELEASE_ROOT_URL="$(manifest_value release_root_url)"
  [ "$RELEASE_ROOT_URL" = "${NEXUS_BASE_URL%/}/repository/${NEXUS_REPOSITORY}/org/linphone" ] || die "unexpected staged Nexus root"
  if [ -n "${GITHUB_SHA:-}" ]; then
    [ "$SOURCE_SHORT_SHA" = "${GITHUB_SHA:0:9}" ] || die "staged source SHA does not match GITHUB_SHA"
    [ "$RELEASE_VERSION" = "${SDK_VERSION_BASE}-${GITHUB_SHA:0:9}" ] || die "staged release version does not match GITHUB_SHA"
  fi
  UPLOAD_FILES=()
  [ "$(find "${STAGING_DIR}/maven" -type f | wc -l | tr -d ' ')" = 10 ] \
    || die "staged Maven payload must contain exactly 10 immutable assets"
  for artifact_id in "${ARTIFACT_IDS[@]}"; do
    validate_version_dir "${STAGING_DIR}/maven" "$artifact_id"
    while IFS= read -r name; do
      rel="${artifact_id}/${RELEASE_VERSION}/${name}"
      expected_sha="$(awk -v path="$rel" '$1==path {print $2}' "${STAGING_DIR}/release-manifest.txt")"
      [ -n "$expected_sha" ] && [ "$expected_sha" = "$(sha256_file "${STAGING_DIR}/maven/${rel}")" ] || die "manifest checksum mismatch for ${rel}"
      UPLOAD_FILES+=("$rel")
    done < <(expected_names "$artifact_id")
  done
}

remote_url() { printf '%s/%s' "$RELEASE_ROOT_URL" "$1"; }
head_status() { curl --silent --show-error --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" --head --output /dev/null --write-out '%{http_code}' "$1" || true; }
assert_missing() {
  local url="$(remote_url "$1")" code=""
  code="$(head_status "$url")"
  [ "$code" = 404 ] || { [ "$code" = 200 ] && die "refusing to overwrite ${url}"; die "unexpected HTTP ${code} for ${url}"; }
}

preflight() {
  local rel=""
  [ -n "$NEXUS_USERNAME" ] || die "Nexus username is required"
  [ -n "$NEXUS_PASSWORD" ] || die "Nexus password is required"
  for rel in "${UPLOAD_FILES[@]}"; do assert_missing "$rel"; done
}

publish() {
  local rel="" url=""
  for rel in "${UPLOAD_FILES[@]}"; do
    assert_missing "$rel"
    url="$(remote_url "$rel")"
    curl --fail --silent --show-error --header 'If-None-Match: *' --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" --upload-file "${STAGING_DIR}/maven/${rel}" "$url"
  done
}

verify_remote() {
  local rel="" downloaded=""
  for rel in "${UPLOAD_FILES[@]}"; do
    downloaded="${STAGING_DIR}/verified/${rel}"
    mkdir -p "$(dirname "$downloaded")"
    curl --fail --silent --show-error --user "${NEXUS_USERNAME}:${NEXUS_PASSWORD}" --output "$downloaded" "$(remote_url "$rel")"
    [ "$(sha256_file "$downloaded")" = "$(sha256_file "${STAGING_DIR}/maven/${rel}")" ] || die "downloaded checksum mismatch for ${rel}"
  done
}

emit_outputs() {
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  printf 'release_version=%s\nstaging_dir=%s\n' "$RELEASE_VERSION" "$STAGING_DIR" >> "$GITHUB_OUTPUT"
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --build-dir) BUILD_DIR="$2"; shift 2;;
      --staging-dir) STAGING_DIR="$2"; shift 2;;
      --android-archs) ANDROID_ARCHS="$2"; shift 2;;
      --nexus-base-url) NEXUS_BASE_URL="$2"; shift 2;;
      --nexus-repository) NEXUS_REPOSITORY="$2"; shift 2;;
      --nexus-username) NEXUS_USERNAME="$2"; shift 2;;
      --nexus-password) NEXUS_PASSWORD="$2"; shift 2;;
      --build-only) BUILD_ONLY=true; shift;;
      --publish-staged) PUBLISH_STAGED=true; shift;;
      --dry-run) DRY_RUN=true; shift;;
      --skip-build) SKIP_BUILD=true; shift;;
      --help) usage; exit 0;;
      *) die "unknown argument $1";;
    esac
  done
}

main() {
  parse_args "$@"
  validate_build_jobs
  $BUILD_ONLY && $PUBLISH_STAGED && die "--build-only and --publish-staged are mutually exclusive"
  $BUILD_ONLY && $DRY_RUN && die "--build-only and --dry-run are mutually exclusive"
  require_cmd curl; require_cmd shasum; require_cmd unzip; require_cmd python3
  if $PUBLISH_STAGED; then load_staged; else
    require_cmd cmake; require_cmd git
    derive_release_context; build_sdk; stage_build
  fi
  emit_outputs
  if $BUILD_ONLY; then log "build-only complete: ${RELEASE_VERSION}"; return; fi
  preflight
  if $DRY_RUN; then log "dry-run complete: ${RELEASE_VERSION}"; return; fi
  publish; verify_remote
  log "publish complete and verified: ${RELEASE_VERSION}"
}

main "$@"
