#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEST_ROOT="$(mktemp -d)"
BUILD_DIR="${TEST_ROOT}/build"
PACKAGE_DIR="${BUILD_DIR}/linphone-sdk-swift-ios"
RAW_XCFRAMEWORK_DIR="${BUILD_DIR}/linphone-sdk/apple-darwin/XCFrameworks"
REMOTE_DIR="${TEST_ROOT}/remote"
BUILD_ONLY_STAGING_DIR="${TEST_ROOT}/build-only-staging"
PORT_FILE="${TEST_ROOT}/server-port"
SERVER_LOG="${TEST_ROOT}/server.log"
REQUEST_LOG="${TEST_ROOT}/requests.log"
OTOOL_STUB="${TEST_ROOT}/otool-stub.sh"

EXPECTED_TARGETS=(
  bctoolbox
  bctoolbox-ios
  belcard
  belle-sip
  belr
  lime
  linphone
  mediastreamer2
  msamr
  mscodec2
  msopenh264
  mswebrtc
  ortp
)

cleanup() {
  if [ -n "${SERVER_PID:-}" ]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

mkdir -p "${PACKAGE_DIR}/XCFrameworks" "${PACKAGE_DIR}/Sources/linphonesw" "${PACKAGE_DIR}/Sources/linphonexcframeworks" "${RAW_XCFRAMEWORK_DIR}" "${REMOTE_DIR}"

cat > "${BUILD_DIR}/CMakeCache.txt" <<'EOF'
LINPHONESDK_VERSION_CACHED:STRING=5.5.12+6308ecb470
EOF

cat > "${PACKAGE_DIR}/README.md" <<'EOF'
# Test package
EOF

cat > "${PACKAGE_DIR}/LICENSE.txt" <<'EOF'
Test license
EOF

cat > "${PACKAGE_DIR}/VERSION" <<'EOF'
5.5.12+6308ecb470
EOF

cat > "${PACKAGE_DIR}/Sources/linphonesw/LinphoneWrapper.swift" <<'EOF'
public struct DummyWrapper {}
EOF

cat > "${PACKAGE_DIR}/Sources/linphonesw/LinphoneSdkInfos.swift" <<'EOF'
public struct LinphoneSdkInfos {}
EOF

cat > "${PACKAGE_DIR}/Sources/linphonexcframeworks/Dummy.swift" <<'EOF'
public struct DummyBinaryTarget {}
EOF

cat > "${OTOOL_STUB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = "-L" ] || exit 2
binary="$2"
deps_file="${binary}.deps"
printf '%s:\n' "${binary}"
if [ -f "${deps_file}" ]; then
  while IFS= read -r dep; do
    [ -n "${dep}" ] || continue
    printf '\t%s (compatibility version 1.0.0, current version 1.0.0)\n' "${dep}"
  done < "${deps_file}"
fi
printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1.0.0)\n'
EOF
chmod +x "${OTOOL_STUB}"

for target in "${EXPECTED_TARGETS[@]}"; do
  fixture_dir="${TEST_ROOT}/${target}.xcframework"
  raw_fixture_dir="${RAW_XCFRAMEWORK_DIR}/${target}.xcframework"
  mkdir -p \
    "${fixture_dir}/ios-arm64/dSYMs/${target}.framework.dSYM/Contents/Resources/DWARF" \
    "${fixture_dir}/ios-arm64_x86_64-simulator/dSYMs/${target}.framework.dSYM/Contents/Resources/DWARF" \
    "${raw_fixture_dir}/ios-arm64/${target}.framework" \
    "${raw_fixture_dir}/ios-arm64_x86_64-simulator/${target}.framework"
  printf '%s\n' "${target}-device" > "${fixture_dir}/ios-arm64/${target}"
  printf '%s\n' "${target}-sim" > "${fixture_dir}/ios-arm64_x86_64-simulator/${target}"
  printf '%s\n' "${target}-device-symbols" > "${fixture_dir}/ios-arm64/dSYMs/${target}.framework.dSYM/Contents/Resources/DWARF/${target}"
  printf '%s\n' "${target}-sim-symbols" > "${fixture_dir}/ios-arm64_x86_64-simulator/dSYMs/${target}.framework.dSYM/Contents/Resources/DWARF/${target}"
  printf '%s\n' "${target}-device-binary" > "${raw_fixture_dir}/ios-arm64/${target}.framework/${target}"
  printf '%s\n' "${target}-sim-binary" > "${raw_fixture_dir}/ios-arm64_x86_64-simulator/${target}.framework/${target}"
  cat > "${fixture_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>AvailableLibraries</key><array>
<dict><key>LibraryIdentifier</key><string>ios-arm64</string><key>DebugSymbolsPath</key><string>dSYMs</string></dict>
<dict><key>LibraryIdentifier</key><string>ios-arm64_x86_64-simulator</string><key>DebugSymbolsPath</key><string>dSYMs</string></dict>
</array></dict></plist>
EOF
  (
    cd "${TEST_ROOT}"
    zip -rq "${PACKAGE_DIR}/XCFrameworks/${target}.xcframework.zip" "${target}.xcframework"
  )
  rm -rf "${fixture_dir}"
done

cat > "${RAW_XCFRAMEWORK_DIR}/linphone.xcframework/ios-arm64/linphone.framework/linphone.deps" <<'EOF'
@rpath/lime.framework/lime
@rpath/belle-sip.framework/belle-sip
EOF
cat > "${RAW_XCFRAMEWORK_DIR}/linphone.xcframework/ios-arm64_x86_64-simulator/linphone.framework/linphone.deps" <<'EOF'
@rpath/lime.framework/lime
@rpath/belle-sip.framework/belle-sip
EOF
cat > "${RAW_XCFRAMEWORK_DIR}/lime.xcframework/ios-arm64/lime.framework/lime.deps" <<'EOF'
@rpath/bctoolbox.framework/bctoolbox
EOF
cat > "${RAW_XCFRAMEWORK_DIR}/lime.xcframework/ios-arm64_x86_64-simulator/lime.framework/lime.deps" <<'EOF'
@rpath/bctoolbox.framework/bctoolbox
EOF

{
  cat <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "linphonesw",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "linphonesw",
            targets: ["linphonesw"]
        )
    ],
    targets: [
EOF
  for target in "${EXPECTED_TARGETS[@]}"; do
    cat <<EOF
        .binaryTarget(
            name: "${target}",
            url: "https://invalid.example/linphone-sdk-swift-ios-5.5.12+6308ecb470/XCFrameworks/${target}.xcframework.zip",
            checksum: "fixture-${target}"
        ),
EOF
  done
  printf '        .target(\n'
  printf '            name: "linphonexcframeworks",\n'
  printf '            dependencies: ['
  first=true
  for target in "${EXPECTED_TARGETS[@]}"; do
    if $first; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "${target}"
  done
  cat <<'EOF'
]
        ),
        .target(
            name: "linphonesw",
            dependencies: ["linphonexcframeworks"]
        )
    ]
)
EOF
} > "${PACKAGE_DIR}/Package.swift"

MISSING_DSYM_BUILD_DIR="${TEST_ROOT}/missing-dsym-build"
cp -R "${BUILD_DIR}" "${MISSING_DSYM_BUILD_DIR}"
zip -dq \
  "${MISSING_DSYM_BUILD_DIR}/linphone-sdk-swift-ios/XCFrameworks/linphone.xcframework.zip" \
  'linphone.xcframework/ios-arm64/dSYMs/*'
set +e
OTOOL_BIN="${OTOOL_STUB}" bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --skip-build \
  --build-only \
  --build-dir "${MISSING_DSYM_BUILD_DIR}" \
  --staging-dir "${TEST_ROOT}/missing-dsym-staging"
MISSING_DSYM_STATUS=$?
set -e
[ "${MISSING_DSYM_STATUS}" -ne 0 ] || {
  echo "expected staging to reject an XCFramework without a device dSYM" >&2
  exit 1
}

MISSING_RUNTIME_BUILD_DIR="${TEST_ROOT}/missing-runtime-build"
cp -R "${BUILD_DIR}" "${MISSING_RUNTIME_BUILD_DIR}"
{
  cat <<'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "linphonesw",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "linphonesw",
            targets: ["linphonesw"]
        )
    ],
    targets: [
EOF
  for target in "${EXPECTED_TARGETS[@]}"; do
    [ "${target}" = "lime" ] && continue
    cat <<EOF
        .binaryTarget(
            name: "${target}",
            url: "https://invalid.example/linphone-sdk-swift-ios-5.5.12+6308ecb470/XCFrameworks/${target}.xcframework.zip",
            checksum: "fixture-${target}"
        ),
EOF
  done
  printf '        .target(\n'
  printf '            name: "linphonexcframeworks",\n'
  printf '            dependencies: ['
  first=true
  for target in "${EXPECTED_TARGETS[@]}"; do
    [ "${target}" = "lime" ] && continue
    if $first; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "${target}"
  done
  cat <<'EOF'
]
        ),
        .target(
            name: "linphonesw",
            dependencies: ["linphonexcframeworks"]
        )
    ]
)
EOF
} > "${MISSING_RUNTIME_BUILD_DIR}/linphone-sdk-swift-ios/Package.swift"
rm "${MISSING_RUNTIME_BUILD_DIR}/linphone-sdk-swift-ios/XCFrameworks/lime.xcframework.zip"
rm -rf "${MISSING_RUNTIME_BUILD_DIR}/linphone-sdk/apple-darwin/XCFrameworks/lime.xcframework"
set +e
OTOOL_BIN="${OTOOL_STUB}" bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --skip-build \
  --build-only \
  --build-dir "${MISSING_RUNTIME_BUILD_DIR}" \
  --staging-dir "${TEST_ROOT}/missing-runtime-staging"
MISSING_RUNTIME_STATUS=$?
set -e
[ "${MISSING_RUNTIME_STATUS}" -ne 0 ] || {
  echo "expected staging to reject a missing runtime-linked XCFramework target" >&2
  exit 1
}

cat > "${TEST_ROOT}/raw_repo_server.py" <<'PY'
import http.server
import os
import socketserver
import sys

root = sys.argv[1]
port_file = sys.argv[2]
request_log = sys.argv[3]

class Handler(http.server.BaseHTTPRequestHandler):
    def _path(self):
        rel = self.path.lstrip("/")
        return os.path.join(root, rel)

    def do_HEAD(self):
        with open(request_log, "a", encoding="utf-8") as handle:
            handle.write(f"HEAD {self.path}\n")
        path = self._path()
        self.send_response(200 if os.path.exists(path) else 404)
        self.end_headers()

    def do_GET(self):
        path = self._path()
        if not os.path.exists(path):
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(os.path.getsize(path)))
        self.end_headers()
        with open(path, "rb") as handle:
            self.wfile.write(handle.read())

    def do_PUT(self):
        path = self._path()
        if self.headers.get("If-None-Match") != "*":
            self.send_response(428)
            self.end_headers()
            return
        if os.path.exists(path):
            self.send_response(412)
            self.end_headers()
            return
        os.makedirs(os.path.dirname(path), exist_ok=True)
        length = int(self.headers.get("Content-Length", "0"))
        with open(path, "wb") as handle:
          handle.write(self.rfile.read(length))
        self.send_response(201)
        self.end_headers()

    def log_message(self, fmt, *args):
        return

with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="utf-8") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY

python3 "${TEST_ROOT}/raw_repo_server.py" "${REMOTE_DIR}" "${PORT_FILE}" "${REQUEST_LOG}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 50); do
  [ -f "${PORT_FILE}" ] && break
  sleep 0.1
done
[ -f "${PORT_FILE}" ] || { echo "server did not start" >&2; exit 1; }
PORT="$(cat "${PORT_FILE}")"
BASE_URL="http://127.0.0.1:${PORT}"
SOURCE_SHORT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short=9 HEAD)"
RELEASE_VERSION="5.5.12-${SOURCE_SHORT_SHA}"

GITHUB_OUTPUT="${TEST_ROOT}/github-output.txt" \
GITHUB_STEP_SUMMARY="${TEST_ROOT}/github-step-summary.md" \
OTOOL_BIN="${OTOOL_STUB}" bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --skip-build \
  --build-only \
  --build-dir "${BUILD_DIR}" \
  --staging-dir "${BUILD_ONLY_STAGING_DIR}" \
  --nexus-base-url "${BASE_URL}" \
  --nexus-username user \
  --nexus-password pass

[ -f "${BUILD_ONLY_STAGING_DIR}/release-manifest.txt" ]
grep -q '^release_version=' "${TEST_ROOT}/github-output.txt"
grep -q -- '- Mode: `build-only`' "${TEST_ROOT}/github-step-summary.md"

bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --publish-staged \
  --dry-run \
  --staging-dir "${BUILD_ONLY_STAGING_DIR}" \
  --nexus-base-url "${BASE_URL}" \
  --nexus-username user \
  --nexus-password pass

[ "$(find "${REMOTE_DIR}" -type f | wc -l | tr -d ' ')" -eq 0 ]
[ "$(grep -c '^HEAD ' "${REQUEST_LOG}")" -eq 1 ]

bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --publish-staged \
  --staging-dir "${BUILD_ONLY_STAGING_DIR}" \
  --nexus-base-url "${BASE_URL}" \
  --nexus-username user \
  --nexus-password pass

[ -f "${BUILD_ONLY_STAGING_DIR}/release-manifest.txt" ]
[ -f "${BUILD_ONLY_STAGING_DIR}/linphone-sdk-swift-ios-source-${RELEASE_VERSION}.zip" ]
[ "$(grep -c '^HEAD ' "${REQUEST_LOG}")" -eq 1 ]

grep -q '^// swift-tools-version:5.7$' "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios/Package.swift"
grep -q '\.iOS(.v15)' "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios/Package.swift"
BINARY_TARGET_COUNT="$(grep -c '\.binaryTarget(' "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios/Package.swift")"
[ "${BINARY_TARGET_COUNT}" -eq 13 ]
grep -q "release_version=${RELEASE_VERSION}" "${BUILD_ONLY_STAGING_DIR}/release-manifest.txt"
grep -q "${BASE_URL}/repository/ios-release/LinphoneSDK/${RELEASE_VERSION}/bctoolbox.xcframework.zip" \
  "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios/Package.swift"
grep -q "${BASE_URL}/repository/ios-release/LinphoneSDK/${RELEASE_VERSION}/lime.xcframework.zip" \
  "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios/Package.swift"
grep -q '^target=lime$' "${BUILD_ONLY_STAGING_DIR}/release-manifest.txt"
grep -q '^runtime_dependency=linphone|ios-arm64|lime$' "${BUILD_ONLY_STAGING_DIR}/release-manifest.txt"
MANIFEST_VALIDATION_DIR="${TEST_ROOT}/manifest-validation"
cp -R "${BUILD_ONLY_STAGING_DIR}/source-bundle/linphone-sdk-swift-ios" "${MANIFEST_VALIDATION_DIR}"
sed -i.bak "s#${BASE_URL}#https://nexus.tools.textnow.io#g" "${MANIFEST_VALIDATION_DIR}/Package.swift"
rm "${MANIFEST_VALIDATION_DIR}/Package.swift.bak"
swift package --package-path "${MANIFEST_VALIDATION_DIR}" dump-package >/dev/null

REMOTE_FILE_COUNT="$(find "${REMOTE_DIR}" -type f | wc -l | tr -d ' ')"
[ "${REMOTE_FILE_COUNT}" -eq 26 ]
[ "$(grep -c '^HEAD ' "${REQUEST_LOG}")" -eq 1 ]
find "${REMOTE_DIR}" -type f | grep -q 'lime\.xcframework\.zip'
if find "${REMOTE_DIR}" -type f | grep -Eq 'linphone-sdk.*(\.podspec|\.zip)$'; then
  echo "unexpected SDK archive or podspec uploaded to remote store" >&2
  exit 1
fi

set +e
bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --publish-staged \
  --staging-dir "${BUILD_ONLY_STAGING_DIR}" \
  --nexus-base-url "${BASE_URL}" \
  --nexus-username user \
  --nexus-password pass
CONDITIONAL_PUT_STATUS=$?
set -e

[ "${CONDITIONAL_PUT_STATUS}" -ne 0 ] || {
  echo "expected conditional PUT to reject an existing remote file" >&2
  exit 1
}
[ "$(grep -c '^HEAD ' "${REQUEST_LOG}")" -eq 1 ]
[ "$(find "${REMOTE_DIR}" -type f | wc -l | tr -d ' ')" -eq 26 ]

set +e
bash "${REPO_ROOT}/scripts/ios-release-publish.sh" \
  --publish-staged \
  --dry-run \
  --staging-dir "${BUILD_ONLY_STAGING_DIR}" \
  --nexus-base-url "${BASE_URL}" \
  --nexus-username user \
  --nexus-password pass
STATUS=$?
set -e

[ "${STATUS}" -ne 0 ] || {
  echo "expected dry-run overwrite preflight to fail once remote files exist" >&2
  exit 1
}
[ "$(grep -c '^HEAD ' "${REQUEST_LOG}")" -eq 2 ]

echo "ios release publish fixture test passed"
