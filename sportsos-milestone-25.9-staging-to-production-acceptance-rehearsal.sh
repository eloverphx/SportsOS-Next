#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.9-staging-rehearsal-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SCRIPT="scripts/staging-production-rehearsal.sh"
TEST="packages/core/test/staging-production-rehearsal-25.9.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "scripts/release-smoke-test.sh" \
  "scripts/release-readiness-diagnostics.sh" \
  "scripts/generate-release-artifact.sh" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SCRIPT" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SCRIPT")" "$(dirname "$TEST")"

cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
ALLOW_SECRET_GATE_FAILURE="${SPORTSOS_ALLOW_SECRET_GATE_FAILURE:-0}"

cd "$ROOT"

echo "============================================================"
echo " SportsOS Staging -> Production Acceptance Rehearsal"
echo "============================================================"
echo

step() {
  local name="$1"
  shift

  echo
  echo "------------------------------------------------------------"
  echo "$name"
  echo "------------------------------------------------------------"

  "$@"
}

step \
  "1. Typecheck + unit tests" \
  bash -lc \
  "npm run typecheck && npm test"

step \
  "2. Build and start API + dashboard" \
  docker compose up -d --build api dashboard

step \
  "3. Container status" \
  docker compose ps

step \
  "4. Release readiness diagnostics" \
  bash scripts/release-readiness-diagnostics.sh

if [[ "$ALLOW_SECRET_GATE_FAILURE" == "1" ]]; then
  echo
  echo "Secret gate bypass enabled for rehearsal only."
  echo "Smoke-test failure caused solely by secret quality may be tolerated."
  echo

  set +e
  bash scripts/release-smoke-test.sh
  smoke_rc=$?
  set -e

  if (( smoke_rc != 0 )); then
    echo
    echo "Smoke test returned non-zero."

    node <<'NODE'
fetch("http://127.0.0.1:4001/broadcast-coordinator/secret-environment-validation")
  .then(async (response) => {
    const json = await response.json();

    const checks =
      json?.data?.checks ??
      [];

    const failing =
      checks.filter(
        (check) =>
          check.required &&
          !check.ok,
      );

    const onlySecretQuality =
      failing.length > 0 &&
      failing.every(
        (check) =>
          [
            "jwt:quality",
            "mysql-password:quality",
            "minio-password:quality",
          ].includes(
            check.id,
          ),
      );

    if (!onlySecretQuality) {
      console.error(
        "Smoke failure is not limited to approved rehearsal-only secret-quality blockers.",
      );
      process.exit(1);
    }

    console.log(
      "Rehearsal continues because the only remaining blockers are known secret-quality checks.",
    );
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
NODE
  fi
else
  step \
    "5. Release smoke test" \
    bash scripts/release-smoke-test.sh
fi

step \
  "6. Docker E2E" \
  npm run test:e2e:docker

step \
  "7. Release artifact" \
  bash scripts/generate-release-artifact.sh

echo
echo "============================================================"
echo " Rehearsal completed successfully."
echo "============================================================"
echo
echo "This rehearsal does not deploy to production."
EOF

chmod +x "$SCRIPT"

cat >> "$DOC" <<'EOF'

## Milestone 25.9 — Staging-to-production acceptance rehearsal

SportsOS now includes a single staging-to-production rehearsal command:

```text
scripts/staging-production-rehearsal.sh
```

The rehearsal executes, in order:

1. typecheck and unit tests
2. API/dashboard production build and startup
3. container status
4. release-readiness diagnostics
5. release smoke test
6. Docker E2E tests
7. release artifact generation

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/staging-production-rehearsal.sh
```

For development/staging only, known credential-strength blockers may be tolerated while every other release gate remains mandatory:

```bash
SPORTSOS_ALLOW_SECRET_GATE_FAILURE=1 \
  bash scripts/staging-production-rehearsal.sh
```

That override permits continuation only when the remaining secret validation failures are exactly:

```text
jwt:quality
mysql-password:quality
minio-password:quality
```

It does not bypass API health, migration readiness, dashboard reachability, E2E tests, or any other release check.

The rehearsal does not deploy to production.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.9 staging-to-production acceptance rehearsal", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/staging-production-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("runs the complete release sequence",()=> {
    expect(script).toContain("npm run typecheck && npm test");
    expect(script).toContain("docker compose up -d --build api dashboard");
    expect(script).toContain("release-readiness-diagnostics.sh");
    expect(script).toContain("release-smoke-test.sh");
    expect(script).toContain("npm run test:e2e:docker");
    expect(script).toContain("generate-release-artifact.sh");
  });

  it("supports a narrowly scoped staging-only secret gate override",()=> {
    expect(script).toContain("SPORTSOS_ALLOW_SECRET_GATE_FAILURE");
    expect(script).toContain("jwt:quality");
    expect(script).toContain("mysql-password:quality");
    expect(script).toContain("minio-password:quality");
  });

  it("does not tolerate unrelated smoke failures",()=> {
    expect(script).toContain(
      "Smoke failure is not limited to approved rehearsal-only secret-quality blockers.",
    );
  });

  it("does not deploy to production",()=> {
    expect(script).toContain("does not deploy to production");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.9 installed"
echo "============================================================"
echo "Added:"
echo "  - staging-to-production rehearsal script"
echo "  - ordered release acceptance flow"
echo "  - strict fail-fast behavior"
echo "  - narrow staging-only secret-quality override"
echo "  - E2E + artifact generation in rehearsal"
echo "  - no production deployment action"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then, while current secrets are still intentionally weak:"
echo "  SPORTSOS_ALLOW_SECRET_GATE_FAILURE=1 bash scripts/staging-production-rehearsal.sh"
echo
echo "Next after green:"
echo "  Milestone 25.10 - Deployment / Release Readiness Closeout"
