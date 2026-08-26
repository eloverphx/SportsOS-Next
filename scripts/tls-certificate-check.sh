#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ENV_FILE="${SPORTSOS_ENV_FILE:-${ROOT}/.env}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS TLS Certificate Validation"
echo "============================================================"

[[ -f "$ENV_FILE" ]] || {
  echo "FAIL  environment file missing: $ENV_FILE" >&2
  exit 1
}

get_env() {
  local name="$1"

  awk -v key="$name" '
    index($0, key "=") == 1 {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$ENV_FILE"
}

PUBLIC_API_URL="$(get_env PUBLIC_API_URL)"
DASHBOARD_ORIGIN="$(get_env DASHBOARD_ORIGIN)"
MIN_DAYS="$(get_env SPORTSOS_TLS_MIN_DAYS)"

MIN_DAYS="${MIN_DAYS:-14}"

node - "$PUBLIC_API_URL" "$DASHBOARD_ORIGIN" "$MIN_DAYS" <<'NODE'
const [
  apiUrl,
  dashboardUrl,
  minDaysRaw,
] = process.argv.slice(2);

const minDays =
  Number(minDaysRaw);

if (
  !Number.isFinite(minDays) ||
  minDays < 1
) {
  console.error(
    "FAIL  invalid SPORTSOS_TLS_MIN_DAYS",
  );
  process.exit(1);
}

const urls = [
  apiUrl,
  dashboardUrl,
];

const hosts = [];

for (const value of urls) {
  try {
    const url =
      new URL(value);

    if (url.protocol !== "https:") {
      console.error(
        `FAIL  ${value || "(empty)"} is not https://`,
      );
      process.exit(1);
    }

    if (!hosts.includes(url.hostname)) {
      hosts.push(url.hostname);
    }
  } catch {
    console.error(
      `FAIL  invalid HTTPS URL: ${value || "(empty)"}`,
    );
    process.exit(1);
  }
}

console.log(
  `Targets: ${hosts.join(", ")}`,
);

console.log(
  `Minimum certificate lifetime: ${minDays} day(s)`,
);
NODE

failures=0

validate_host() {
  local host="$1"

  echo
  echo "Checking ${host}..."

  cert="$(
    timeout 15 \
      openssl s_client \
        -connect "${host}:443" \
        -servername "${host}" \
        -verify_return_error \
        -showcerts \
        </dev/null \
        2>/dev/null |
      openssl x509 \
        -noout \
        -subject \
        -issuer \
        -dates \
        -ext subjectAltName \
        2>/dev/null
  )" || {
    echo "FAIL  TLS connection/certificate chain for ${host}"
    failures=$((failures + 1))
    return
  }

  if [[ -z "$cert" ]]; then
    echo "FAIL  no certificate returned for ${host}"
    failures=$((failures + 1))
    return
  fi

  echo "$cert"

  if timeout 15 \
    openssl s_client \
      -connect "${host}:443" \
      -servername "${host}" \
      -verify_return_error \
      </dev/null \
      >/dev/null 2>&1
  then
    echo "PASS  certificate chain validates"
  else
    echo "FAIL  certificate chain validation"
    failures=$((failures + 1))
  fi

  if timeout 15 \
    openssl s_client \
      -connect "${host}:443" \
      -servername "${host}" \
      </dev/null \
      2>/dev/null |
    openssl x509 \
      -noout \
      -checkhost "${host}" \
      >/dev/null 2>&1
  then
    echo "PASS  hostname matches certificate"
  else
    echo "FAIL  hostname mismatch"
    failures=$((failures + 1))
  fi

  seconds="$(
    node - "$MIN_DAYS" <<'NODE'
const days =
  Number(process.argv[2]);

console.log(
  Math.trunc(
    days * 86400,
  ),
);
NODE
  )"

  if timeout 15 \
    openssl s_client \
      -connect "${host}:443" \
      -servername "${host}" \
      </dev/null \
      2>/dev/null |
    openssl x509 \
      -noout \
      -checkend "$seconds" \
      >/dev/null 2>&1
  then
    echo "PASS  certificate remains valid for at least ${MIN_DAYS} day(s)"
  else
    echo "FAIL  certificate expires within ${MIN_DAYS} day(s)"
    failures=$((failures + 1))
  fi
}

hosts="$(
  node - "$PUBLIC_API_URL" "$DASHBOARD_ORIGIN" <<'NODE'
for (
  const value
  of process.argv.slice(2)
) {
  try {
    const host =
      new URL(value)
        .hostname;

    if (host) {
      console.log(host);
    }
  } catch {}
}
NODE
)"

unique_hosts="$(
  printf '%s\n' "$hosts" |
    awk 'NF && !seen[$0]++'
)"

while IFS= read -r host; do
  [[ -n "$host" ]] || continue
  validate_host "$host"
done <<< "$unique_hosts"

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "TLS certificate validation FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "TLS certificate validation PASSED."
