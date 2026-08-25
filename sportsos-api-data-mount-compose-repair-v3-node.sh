#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
COMPOSE="${ROOT}/docker-compose.yml"
DATA_DIR="${ROOT}/data"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${COMPOSE}.before-api-data-mount-${STAMP}"

cd "$ROOT"

[[ -f "$COMPOSE" ]] || {
  echo "ERROR: missing $COMPOSE" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || {
  echo "ERROR: node is required on the Unraid host." >&2
  exit 1
}

cp -a "$COMPOSE" "$BACKUP"

mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"
chmod -R 775 "$DATA_DIR"

node <<'NODE'
const fs = require("fs");

const compose =
  "/mnt/user/appdata/SportsOS-Next/docker-compose.yml";

let text =
  fs.readFileSync(compose, "utf8");

const apiStart = text.indexOf("  api:\n");
if (apiStart < 0) throw new Error("api service not found");

const apiEnd = text.indexOf("\n  dashboard:\n", apiStart);
if (apiEnd < 0) throw new Error("dashboard boundary not found");

const before = text.slice(0, apiStart);
let api = text.slice(apiStart, apiEnd);
const after = text.slice(apiEnd);

if (!api.includes("      SPORTSOS_DATA_DIR: /app/data\n")) {
  const envMarker =
    "      MINIO_SECRET_KEY: ${MINIO_ROOT_PASSWORD}\n";

  if (!api.includes(envMarker)) {
    throw new Error("API environment insertion marker not found");
  }

  api = api.replace(
    envMarker,
    envMarker + "      SPORTSOS_DATA_DIR: /app/data\n",
  );
}

const volumeLine =
  "      - /mnt/user/appdata/SportsOS-Next/data:/app/data\n";

if (!api.includes(volumeLine)) {
  const portsMarker =
    '    ports:\n      - "4001:4001"\n';

  if (!api.includes(portsMarker)) {
    throw new Error("API ports insertion marker not found");
  }

  api = api.replace(
    portsMarker,
    "    volumes:\n" +
      volumeLine +
      portsMarker,
  );
}

fs.writeFileSync(
  compose,
  before + api + after,
);

console.log("docker-compose.yml patched successfully.");
NODE

echo
echo "========== PATCHED API SOURCE =========="
sed -n '70,120p' "$COMPOSE"

echo
echo "========== EFFECTIVE API CONFIG =========="
docker compose config | sed -n '/^  api:/,/^  dashboard:/p'

echo
echo "========== REQUIRED CHECKS =========="

docker compose config | grep -q 'SPORTSOS_DATA_DIR: /app/data' || {
  echo "ERROR: effective compose missing SPORTSOS_DATA_DIR" >&2
  exit 1
}

docker compose config | grep -q '/mnt/user/appdata/SportsOS-Next/data' || {
  echo "ERROR: effective compose missing host data bind mount" >&2
  exit 1
}

docker compose config | grep -q 'target: /app/data' || {
  echo "ERROR: effective compose missing /app/data mount target" >&2
  exit 1
}

echo "PASS: effective Compose contains SPORTSOS_DATA_DIR=/app/data"
echo "PASS: effective Compose contains persistent API data bind mount"

echo
echo "Backup:"
echo "  $BACKUP"

echo
echo "Next:"
echo "  docker compose up -d --build --force-recreate api"
