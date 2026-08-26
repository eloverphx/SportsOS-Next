#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"

cd "$ROOT"

get_env() {
  local name="$1"
  awk -v key="$name" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$ENV_FILE"
}

API="$(get_env PUBLIC_API_URL)"
POLLING="${API}/socket.io/?EIO=4&transport=polling"

echo "============================================================"
echo " SportsOS External Realtime Verification"
echo "============================================================"
echo "Polling target: ${POLLING}"

node - "$POLLING" <<'NODE'
const url = process.argv[2];

const response = await fetch(url, { redirect: "manual" });
const text = await response.text();

console.log(`HTTP ${response.status}`);
console.log(text.slice(0, 160));

if (!response.ok) {
  console.error("FAIL  polling endpoint");
  process.exit(1);
}

if (!text.includes('"sid"')) {
  console.error("FAIL  Socket.IO handshake missing sid");
  process.exit(1);
}

if (!text.includes('"websocket"')) {
  console.error("FAIL  Socket.IO handshake does not advertise websocket upgrade");
  process.exit(1);
}

console.log("PASS  Socket.IO handshake returned sid");
console.log("PASS  WebSocket upgrade advertised");
NODE
