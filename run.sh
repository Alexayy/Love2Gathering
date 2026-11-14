#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$PROJECT_ROOT"
if [[ "${1:-}" == '--help' ]]; then
  printf 'Usage: ./run.sh [--services-only | LÖVE arguments]\nStarts the catalog, XMage and the desktop client. First launch builds XMage.\n'
  exit 0
fi
# Also use a JDK already installed by local development/build setup.
if ! command -v java >/dev/null 2>&1; then
  for task_java in "$PROJECT_ROOT"/.tools/jdk-*/bin/java; do
    if [[ -x "$task_java" ]]; then
      export JAVA_HOME="${task_java%/bin/java}"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi
for executable in python3 love; do
  if ! command -v "$executable" >/dev/null 2>&1; then printf 'Please install %s before starting.\n' "$executable" >&2; exit 1; fi
done
# Preserve genuine user overrides while allowing Settings to replace paths
# that a previous launcher resolved automatically.
if [[ -z "${LOVE2GATHERING_DATA_DIR_EXPLICIT+x}" ]]; then
  if [[ -n "${LOVE2GATHERING_DATA_DIR:-}" && -z "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then export LOVE2GATHERING_DATA_DIR_EXPLICIT=1;else export LOVE2GATHERING_DATA_DIR_EXPLICIT=0;fi
fi
if [[ -z "${LOVE2GATHERING_CACHE_DIR_EXPLICIT+x}" ]]; then
  if [[ -n "${LOVE2GATHERING_CACHE_DIR:-}" && -z "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then export LOVE2GATHERING_CACHE_DIR_EXPLICIT=1;else export LOVE2GATHERING_CACHE_DIR_EXPLICIT=0;fi
fi
if [[ -n "${LOVE2GATHERING_STORAGE_RESOLVED:-}" ]]; then
  if [[ "$LOVE2GATHERING_DATA_DIR_EXPLICIT" == 0 ]]; then unset LOVE2GATHERING_DATA_DIR;fi
  if [[ "$LOVE2GATHERING_CACHE_DIR_EXPLICIT" == 0 ]]; then unset LOVE2GATHERING_CACHE_DIR;fi
fi
mkdir -p .runtime
PATH_RESOLUTION_ERROR=''
USER_DATA_DIR=''
USER_CACHE_DIR=''
if USER_DATA_DIR=$(python3 service/paths.py --next 2>&1); then
  if USER_CACHE_DIR=$(python3 service/paths.py --cache --next 2>&1); then :
  else PATH_RESOLUTION_ERROR="${USER_CACHE_DIR##*$'\n'}";USER_CACHE_DIR='';fi
else PATH_RESOLUTION_ERROR="${USER_DATA_DIR##*$'\n'}";USER_DATA_DIR='';fi
OWNED_PIDS=()
BUILD_PID=''
ENGINE_PID=''
CLIENT_PID=''
STARTUP_FILE=''
cleanup() {
  if [[ -n "$BUILD_PID" ]]; then kill -- "-$BUILD_PID" 2>/dev/null || true; fi
  # Finalize the owned match while its catalog can still commit the last frame.
  if [[ -n "$ENGINE_PID" ]] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    python3 - "$ENGINE_PORT" <<'PYSTOP'
import sys,urllib.request
try:
    request=urllib.request.Request('http://127.0.0.1:'+sys.argv[1]+'/session/stop',data=b'{}',headers={'Content-Type':'application/json'},method='POST')
    with urllib.request.urlopen(request,timeout=9) as response: response.read()
except Exception: pass # The durable SQLite outbox is recovered on the next start.
PYSTOP
  fi
  for process_id in "${OWNED_PIDS[@]}"; do kill "$process_id" 2>/dev/null || true; done
  if [[ -n "$STARTUP_FILE" ]]; then rm -f -- "$STARTUP_FILE"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
healthy() {
  python3 - "$1" "${2:-any}" "$USER_DATA_DIR" "$USER_CACHE_DIR" <<'PY'
import json, os, pathlib, sys, urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:'+sys.argv[1]+'/health', timeout=1) as response:
        data=json.load(response)
    assert data.get('status')=='ok' or data.get('engine')=='XMage'
    if sys.argv[2]=='catalog':
        assert data.get('apiVersion',0)>=10
        assert data.get('storage',{}).get('dataDirectory')==sys.argv[3]
        assert data.get('storage',{}).get('separateCache',False)==bool(sys.argv[4])
        if sys.argv[4]:assert data.get('storage',{}).get('cacheDirectory')==sys.argv[4]
        source=os.environ.get('LOVE2GATHERING_CATALOG_SOURCE')
        if source:
            assert data.get('catalogSource')==str(pathlib.Path(source).resolve())
except Exception:
    raise SystemExit(1)
PY
}
free_port() {
  python3 - "$1" "${2:-0}" <<'PYPORT'
import socket,sys
start=int(sys.argv[1]); excluded=int(sys.argv[2])
if not 1024 <= start <= 65400: raise SystemExit('Invalid local service port')
for port in range(start,start+100):
    if port==excluded: continue
    with socket.socket() as listener:
        try: listener.bind(('127.0.0.1',port))
        except OSError: continue
    print(port); break
else: raise SystemExit('No free local service port')
PYPORT
}
CATALOG_PORT=${LOVE2GATHERING_CATALOG_PORT:-17370}
START_CATALOG=false
if [[ -n "$PATH_RESOLUTION_ERROR" ]] || ! healthy "$CATALOG_PORT" catalog; then
  CATALOG_PORT=$(free_port "$CATALOG_PORT")
  START_CATALOG=true
fi
# Every desktop instance owns its game engine. Opening a new client cannot
# replace another client's active match, including an older running version.
ENGINE_PORT=$(free_port "${LOVE2GATHERING_ENGINE_PORT:-17371}" "$CATALOG_PORT")
ROOM_PORT=$(free_port "${LOVE2GATHERING_ROOM_PORT:-17380}" "$ENGINE_PORT")
while [[ "$ROOM_PORT" == "$CATALOG_PORT" ]]; do ROOM_PORT=$(free_port "$((ROOM_PORT+1))" "$ENGINE_PORT"); done
export LOVE2GATHERING_CATALOG_PORT="$CATALOG_PORT"
export LOVE2GATHERING_ENGINE_PORT="$ENGINE_PORT"
export LOVE2GATHERING_ROOM_PORT="$ROOM_PORT"
STARTUP_FILE=$(mktemp "$PROJECT_ROOT/.runtime/startup.XXXXXX.json")
export LOVE2GATHERING_STARTUP_STATUS="$STARTUP_FILE"
startup() { python3 scripts/startup-status.py "$STARTUP_FILE" "$1" "$2" "$3" "${4:-loading}"; }
client_open() {
  if [[ -n "$CLIENT_PID" ]] && ! kill -0 "$CLIENT_PID" 2>/dev/null; then wait "$CLIENT_PID" || true;exit 0;fi
}
startup_fail() {
  local code=$1
  trap - ERR
  startup error 0 "Startup could not finish. Check .runtime/catalog.log and engine-build.log." error || true
  if [[ -n "$CLIENT_PID" ]] && kill -0 "$CLIENT_PID" 2>/dev/null; then wait "$CLIENT_PID" || true;fi
  exit "$code"
}
trap 'startup_fail $?' ERR
startup_storage_error() {
  local message=${1#ValueError: }
  startup storage 0.10 "$message" error
  printf '%s\n' "$message" >&2
  # Keep the real early desktop splash visible until its Close control exits.
  if [[ -n "$CLIENT_PID" ]] && kill -0 "$CLIENT_PID" 2>/dev/null; then wait "$CLIENT_PID" || true;fi
  exit 1
}
startup dependencies 0.03 "Checking local dependencies"
if [[ "${1:-}" != '--services-only' ]]; then
  love "$PROJECT_ROOT" "$@" &
  CLIENT_PID=$!;OWNED_PIDS+=("$CLIENT_PID")
fi
if ! command -v java >/dev/null 2>&1; then printf 'Please install Java 21.\n' >&2;false;fi
startup storage 0.10 "Checking saved database and image-cache locations"
if [[ -n "$PATH_RESOLUTION_ERROR" ]]; then startup_storage_error "$PATH_RESOLUTION_ERROR";fi
if ACTIVATION_RESULT=$(python3 service/paths.py --activate-pending 2>&1); then :
else startup_storage_error "${ACTIVATION_RESULT##*$'\n'}";fi
if USER_DATA_DIR=$(python3 service/paths.py 2>&1); then :
else startup_storage_error "${USER_DATA_DIR##*$'\n'}";fi
if USER_CACHE_DIR=$(python3 service/paths.py --cache 2>&1); then :
else startup_storage_error "${USER_CACHE_DIR##*$'\n'}";fi
export LOVE2GATHERING_DATA_DIR="$USER_DATA_DIR"
if [[ -n "$USER_CACHE_DIR" ]]; then export LOVE2GATHERING_CACHE_DIR="$USER_CACHE_DIR";else unset LOVE2GATHERING_CACHE_DIR;fi
export LOVE2GATHERING_STORAGE_RESOLVED=1
startup version 0.18 "Checking the installed client revision and bridge freshness"
# This is an offline revision check. Source updates are never fetched here.
git rev-parse --verify HEAD >/dev/null 2>&1 || true
startup assets 0.23 "Checking supplied fonts and curated assets"
for startup_asset in assets/fonts/Beleren2016-Bold.ttf assets/kenney/runtime/manifest.lua; do
  if [[ ! -f "$startup_asset" ]]; then printf 'Missing startup asset: %s\n' "$startup_asset" >&2;false;fi
done
startup catalog 0.30 "Starting the local catalog and saved data"
if [[ "$START_CATALOG" == true ]]; then
  python3 service/server.py --port "$CATALOG_PORT" --data-dir "$USER_DATA_DIR" >.runtime/catalog.log 2>&1 &
  OWNED_PIDS+=("$!")
fi
if [[ -z "${LOVE2GATHERING_COORDINATOR_TOKEN:-}" ]]; then
  LOVE2GATHERING_COORDINATOR_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
  export LOVE2GATHERING_COORDINATOR_TOKEN
fi
if [[ ! -f bridge/target/xmage-bridge-1.0.0.jar ]] || [[ -n "$(find bridge engine/mage -type d \( -name target -o -name .git \) -prune -o -type f \( -name '*.java' -o -name pom.xml -o -name build_card_map.py \) -newer bridge/target/xmage-bridge-1.0.0.jar -print -quit 2>/dev/null)" ]]; then
    startup build 0.42 "Building pinned XMage and the local bridge"
    printf 'Building XMage and the local bridge. The first build downloads dependencies.\n'
    setsid scripts/build-engine.sh >.runtime/engine-build.log 2>&1 &
    BUILD_PID=$!
    while kill -0 "$BUILD_PID" 2>/dev/null; do
      client_open
      tail -n 1 .runtime/engine-build.log
      sleep 1
    done
    BUILD_OK=true
    wait "$BUILD_PID" || BUILD_OK=false
    BUILD_PID=''
    if [[ "$BUILD_OK" != true ]]; then tail -n 45 .runtime/engine-build.log >&2;false;fi
  fi
startup bridge 0.68 "Starting the XMage bridge"
scripts/run-engine.sh "$ENGINE_PORT" >.runtime/engine.log 2>&1 &
ENGINE_PID=$!
OWNED_PIDS+=("$ENGINE_PID")
for attempt in $(seq 1 30); do
  client_open
  if healthy "$CATALOG_PORT" catalog && healthy "$ENGINE_PORT"; then break; fi
  if [[ "$attempt" == 30 ]]; then printf 'Services could not start. Check .runtime/catalog.log and .runtime/engine.log.\n' >&2;false;fi
  sleep 1
done
startup rooms 0.85 "Starting private room and draft services"
python3 service/rooms.py --port "$ROOM_PORT" --engine-port "$ENGINE_PORT" --catalog-port "$CATALOG_PORT" >.runtime/rooms.log 2>&1 &
OWNED_PIDS+=("$!")
for attempt in $(seq 1 20); do
  client_open
  if healthy "$ROOM_PORT"; then break; fi
  if [[ "$attempt" == 20 ]]; then printf 'The room gateway could not start. Check .runtime/rooms.log.\n' >&2;false;fi
  sleep .2
done
startup ready 1 "Local services are ready" ready
if [[ "${1:-}" == '--services-only' ]]; then
  printf 'Catalog %s; XMage %s; room codes %s. Keep this terminal open.\n' "$CATALOG_PORT" "$ENGINE_PORT" "$ROOM_PORT"
  printf 'Connect with: LOVE2GATHERING_CATALOG_PORT=%s LOVE2GATHERING_ENGINE_PORT=%s LOVE2GATHERING_ROOM_PORT=%s love .\n' "$CATALOG_PORT" "$ENGINE_PORT" "$ROOM_PORT"
  while true; do sleep 1; done
else
  wait "$CLIENT_PID"
fi
