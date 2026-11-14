#!/usr/bin/env bash
# A room host without the graphical client. Only the gateway is network-facing.
set -euo pipefail
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_ROOT"
if [[ "${1:-}" == '--help' ]]; then
  python3 service/rooms.py --help
  printf '\nStarts an owned XMage engine and catalog without LÖVE.\nUse --public-url https://your-server.example with a reachable HTTPS reverse proxy.\n'
  exit 0
fi
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
python3 service/paths.py --activate-pending >/dev/null
export LOVE2GATHERING_DATA_DIR="$(python3 service/paths.py)"
CACHE_DIRECTORY=$(python3 service/paths.py --cache)
if [[ -n "$CACHE_DIRECTORY" ]]; then export LOVE2GATHERING_CACHE_DIR="$CACHE_DIRECTORY";fi
export LOVE2GATHERING_STORAGE_RESOLVED=1
if ! command -v java >/dev/null 2>&1; then
  for task_java in "$PROJECT_ROOT"/.tools/jdk-*/bin/java; do
    if [[ -x "$task_java" ]]; then
      export JAVA_HOME="${task_java%/bin/java}"
      export PATH="$JAVA_HOME/bin:$PATH"
      break
    fi
  done
fi
for executable in java python3; do
  if ! command -v "$executable" >/dev/null 2>&1; then printf 'Please install %s.\n' "$executable" >&2; exit 1; fi
done
if [[ ! -f engine/mage/pom.xml ]]; then git submodule update --init --recursive; fi
mkdir -p .runtime
OWNED_PIDS=()
GATEWAY_PID=''
cleanup() {
  if [[ -n "$GATEWAY_PID" ]]; then
    kill "$GATEWAY_PID" 2>/dev/null || true
    # The gateway closes its own rooms while XMage/catalog are still available.
    for attempt in $(seq 1 50); do
      if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then break; fi
      sleep .1
    done
  fi
  for process_id in "${OWNED_PIDS[@]}"; do kill "$process_id" 2>/dev/null || true; done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
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
    print(port);break
else: raise SystemExit('No free local service port')
PYPORT
}
ROOM_PORT=${LOVE2GATHERING_ROOM_PORT:-17380}
previous_argument=''
for argument in "$@"; do
  if [[ "$previous_argument" == '--port' ]]; then ROOM_PORT=$argument; fi
  if [[ "$argument" == --port=* ]]; then ROOM_PORT=${argument#--port=}; fi
  previous_argument=$argument
done
CATALOG_PORT=$(free_port "${LOVE2GATHERING_CATALOG_PORT:-17370}" "$ROOM_PORT")
ENGINE_PORT=$(free_port "${LOVE2GATHERING_ENGINE_PORT:-17371}" "$CATALOG_PORT")
if [[ "$ENGINE_PORT" == "$ROOM_PORT" ]]; then ENGINE_PORT=$(free_port "$((ENGINE_PORT+1))" "$CATALOG_PORT"); fi
export LOVE2GATHERING_CATALOG_PORT="$CATALOG_PORT"
export LOVE2GATHERING_ENGINE_PORT="$ENGINE_PORT"
if [[ -z "${LOVE2GATHERING_COORDINATOR_TOKEN:-}" ]]; then
  LOVE2GATHERING_COORDINATOR_TOKEN=$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')
  export LOVE2GATHERING_COORDINATOR_TOKEN
fi
if [[ ! -f bridge/target/xmage-bridge-1.0.0.jar ]] || [[ -n "$(find bridge engine/mage -type d \( -name target -o -name .git \) -prune -o -type f \( -name '*.java' -o -name pom.xml -o -name build_card_map.py \) -newer bridge/target/xmage-bridge-1.0.0.jar -print -quit 2>/dev/null)" ]]; then
  scripts/build-engine.sh >.runtime/room-server-build.log 2>&1
fi
python3 service/server.py --port "$CATALOG_PORT" >".runtime/room-server-catalog-$CATALOG_PORT.log" 2>&1 &
OWNED_PIDS+=("$!")
scripts/run-engine.sh "$ENGINE_PORT" >".runtime/room-server-engine-$ENGINE_PORT.log" 2>&1 &
OWNED_PIDS+=("$!")
for attempt in $(seq 1 40); do
  if python3 - "$CATALOG_PORT" "$ENGINE_PORT" <<'PYHEALTH'
import sys,urllib.request
try:
    for port in sys.argv[1:]:
        with urllib.request.urlopen('http://127.0.0.1:'+port+'/health',timeout=1) as response: response.read()
except Exception: raise SystemExit(1)
PYHEALTH
  then break; fi
  if [[ "$attempt" == 40 ]]; then printf 'Room services could not start; see .runtime/room-server-*.log.\n' >&2;exit 1;fi
  sleep .5
done
python3 service/rooms.py "$@" --no-client-api --port "$ROOM_PORT" --engine-port "$ENGINE_PORT" --catalog-port "$CATALOG_PORT" &
GATEWAY_PID=$!
wait "$GATEWAY_PID"
