#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.5-smoke-bundle-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SMOKE="scripts/release-smoke-test.sh"
TEST="packages/core/test/release-smoke-test-25.5.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "docker-compose.yml" \
  "apps/api/src/routes/broadcastSessionCoordinator.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SMOKE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SMOKE")" "$(dirname "$TEST")"

cat > "$SMOKE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"
DASHBOARD_URL="${SPORTSOS_DASHBOARD_URL:-http://127.0.0.1:4000}"

cd "$ROOT"

failures=0

check() {
  local name="$1"
  shift

  if "$@"; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name"
    failures=$((failures + 1))
  fi
}

json_ready() {
  local url="$1"
  node - "$url" <<'NODE'
const url = process.argv[2];

fetch(url)
  .then(async (response) => {
    if (!response.ok) {
      process.exit(1);
    }

    const json = await response.json();

    const ready =
      json?.data?.ready;

    process.exit(
      ready === true
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
}

http_ok() {
  local url="$1"

  node - "$url" <<'NODE'
const url = process.argv[2];

fetch(url)
  .then((response) => {
    process.exit(
      response.ok
        ? 0
        : 1,
    );
  })
  .catch(() => process.exit(1));
NODE
}

container_healthy() {
  local container="$1"

  docker inspect \
    --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
    "$container" 2>/dev/null |
    grep -Eq '^(healthy|running)$'
}

echo "============================================================"
echo " SportsOS Release Smoke Test"
echo "============================================================"
echo

check \
  "API container healthy" \
  container_healthy \
  sportsos_api

check \
  "Dashboard container running" \
  container_healthy \
  sportsos_dashboard

check \
  "API /health" \
  http_ok \
  "${API_URL}/health"

check \
  "Dashboard reachable" \
  http_ok \
  "${DASHBOARD_URL}/"

check \
  "Release readiness" \
  json_ready \
  "${API_URL}/broadcast-coordinator/release-readiness"

check \
  "Data migration readiness" \
  json_ready \
  "${API_URL}/broadcast-coordinator/data-migration-readiness"

check \
  "Secret/environment validation" \
  json_ready \
  "${API_URL}/broadcast-coordinator/secret-environment-validation"

echo
echo "============================================================"

if (( failures > 0 )); then
  echo "Smoke test FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Smoke test PASSED."
EOF

chmod +x "$SMOKE"

cat >> "$DOC" <<'EOF'

## Milestone 25.5 — Health / smoke-test command bundle

SportsOS now includes a reusable deployment smoke test:

```text
scripts/release-smoke-test.sh
```

The bundle checks:

- API container health
- dashboard container state
- API `/health`
- dashboard HTTP reachability
- release readiness
- data migration readiness
- secret/environment validation

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/release-smoke-test.sh
```

Optional overrides:

```text
SPORTSOS_ROOT
SPORTSOS_API_URL
SPORTSOS_DASHBOARD_URL
```

The smoke test exits non-zero when any required check fails, making it suitable for deployment gates and CI/manual release verification.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.5 health / smoke-test command bundle", () => {
  const smoke =
    fs.readFileSync(
      new URL(
        "../../../scripts/release-smoke-test.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("checks API and dashboard containers",()=> {
    expect(smoke).toContain("sportsos_api");
    expect(smoke).toContain("sportsos_dashboard");
    expect(smoke).toContain("container_healthy");
  });

  it("checks API health and dashboard reachability",()=> {
    expect(smoke).toContain("/health");
    expect(smoke).toContain("Dashboard reachable");
  });

  it("checks release readiness endpoints",()=> {
    expect(smoke).toContain("/broadcast-coordinator/release-readiness");
    expect(smoke).toContain("/broadcast-coordinator/data-migration-readiness");
    expect(smoke).toContain("/broadcast-coordinator/secret-environment-validation");
  });

  it("fails with non-zero exit on any failed check",()=> {
    expect(smoke).toContain("failures=$((failures + 1))");
    expect(smoke).toContain("exit 1");
  });

  it("supports deployment URL overrides",()=> {
    expect(smoke).toContain("SPORTSOS_API_URL");
    expect(smoke).toContain("SPORTSOS_DASHBOARD_URL");
    expect(smoke).toContain("SPORTSOS_ROOT");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.5 installed"
echo "============================================================"
echo "Added:"
echo "  - scripts/release-smoke-test.sh"
echo "  - API/dashboard container checks"
echo "  - API health check"
echo "  - dashboard reachability check"
echo "  - release readiness checks"
echo "  - deployment URL overrides"
echo "  - non-zero failure exit"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 25.6 - Rollback / Restore Readiness"
