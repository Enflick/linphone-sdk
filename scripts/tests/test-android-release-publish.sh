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
