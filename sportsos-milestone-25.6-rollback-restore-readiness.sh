#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.6-rollback-readiness-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/rollbackRestoreReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
SCRIPT="scripts/release-rollback-preflight.sh"
TEST="packages/core/test/rollback-restore-readiness-25.6.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "docker-compose.yml" \
  "scripts/release-smoke-test.sh" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$SCRIPT" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$SCRIPT")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type RollbackRestoreCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type RollbackRestoreReadinessInput = {
  root: string;
  dataDir: string | null;
  backupDir: string | null;
};

export type RollbackRestoreReadinessResult = {
  ready: boolean;
  checks: RollbackRestoreCheck[];
};

export function evaluateRollbackRestoreReadiness(
  input: RollbackRestoreReadinessInput,
): RollbackRestoreReadinessResult {
  const checks:
    RollbackRestoreCheck[] =
    [];

  const composeFile =
    path.join(
      input.root,
      "docker-compose.yml",
    );

  const smokeScript =
    path.join(
      input.root,
      "scripts/release-smoke-test.sh",
    );

  checks.push({
    id:
      "rollback:compose-present",
    ok:
      fs.existsSync(
        composeFile,
      ),
    required:
      true,
    message:
      "docker-compose.yml must be present for rollback.",
  });

  checks.push({
    id:
      "rollback:smoke-test-present",
    ok:
      fs.existsSync(
        smokeScript,
      ),
    required:
      true,
    message:
      "Release smoke-test script must be present.",
  });

  const dataDir =
    input.dataDir?.trim() ??
    "";

  checks.push({
    id:
      "restore:data-dir-configured",
    ok:
      Boolean(
        dataDir,
      ),
    required:
      true,
    message:
      dataDir
        ? `Persistent data directory is ${dataDir}.`
        : "Persistent data directory is not configured.",
  });

  if (dataDir) {
    let readable =
      false;

    try {
      fs.accessSync(
        dataDir,
        fs.constants.R_OK,
      );

      readable =
        true;
    } catch {
      readable =
        false;
    }

    checks.push({
      id:
        "restore:data-dir-readable",
      ok:
        readable,
      required:
        true,
      message:
        readable
          ? "Persistent data directory is readable."
          : "Persistent data directory is not readable.",
    });
  }

  const backupDir =
    input.backupDir?.trim() ??
    "";

  checks.push({
    id:
      "restore:backup-dir-configured",
    ok:
      Boolean(
        backupDir,
      ),
    required:
      true,
    message:
      backupDir
        ? `Backup directory is ${backupDir}.`
        : "Backup directory is not configured.",
  });

  if (backupDir) {
    let writable =
      false;

    try {
      fs.mkdirSync(
        backupDir,
        {
          recursive: true,
        },
      );

      fs.accessSync(
        backupDir,
        fs.constants.R_OK |
          fs.constants.W_OK,
      );

      writable =
        true;
    } catch {
      writable =
        false;
    }

    checks.push({
      id:
        "restore:backup-dir-rw",
      ok:
        writable,
      required:
        true,
      message:
        writable
          ? "Backup directory is readable and writable."
          : "Backup directory is not readable and writable.",
    });
  }

  return {
    ready:
      checks
        .filter(
          (check) =>
            check.required,
        )
        .every(
          (check) =>
            check.ok,
        ),
    checks,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateRollbackRestoreReadiness,
} from "../services/rollbackRestoreReadiness.js";`;

if(!s.includes("evaluateRollbackRestoreReadiness")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/rollback-restore-readiness"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/secret-environment-validation",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("25.4 secret-environment-validation route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/rollback-restore-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateRollbackRestoreReadiness({
            root:
              process.cwd(),
            dataDir:
              process.env.SPORTSOS_DATA_DIR ??
              null,
            backupDir:
              process.env.SPORTSOS_BACKUP_DIR ??
              "/app/data/backups",
          }),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="${SPORTSOS_ROOT:-/mnt/user/appdata/SportsOS-Next}"
DATA_DIR="${SPORTSOS_DATA_DIR:-${ROOT}/data}"
BACKUP_DIR="${SPORTSOS_BACKUP_DIR:-${DATA_DIR}/backups}"

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

check \
  "Git repository present" \
  test -d .git

check \
  "Current commit resolvable" \
  git rev-parse --verify HEAD

check \
  "Compose file present" \
  test -f docker-compose.yml

check \
  "Release smoke test present" \
  test -f scripts/release-smoke-test.sh

check \
  "Persistent data directory readable" \
  test -r "$DATA_DIR"

mkdir -p "$BACKUP_DIR"

check \
  "Backup directory writable" \
  test -w "$BACKUP_DIR"

echo
git status --short
echo
git log -1 --oneline --decorate

echo

if (( failures > 0 )); then
  echo "Rollback preflight FAILED: ${failures} check(s) failed."
  exit 1
fi

echo "Rollback preflight PASSED."
echo
echo "This script does not perform a rollback."
echo "It only verifies rollback/restore prerequisites."
EOF

chmod +x "$SCRIPT"

cat >> "$DOC" <<'EOF'

## Milestone 25.6 — Rollback / restore readiness

SportsOS now includes rollback and restore preflight validation.

API:

```text
GET /broadcast-coordinator/rollback-restore-readiness
```

Required checks include:

- compose file present
- release smoke-test script present
- persistent data directory configured/readable
- backup directory configured/readable/writable

Default backup directory:

```text
/app/data/backups
```

Host-side rollback preflight:

```text
scripts/release-rollback-preflight.sh
```

Run:

```bash
cd /mnt/user/appdata/SportsOS-Next
bash scripts/release-rollback-preflight.sh
```

The preflight also verifies the current git commit can be resolved.

Milestone 25.6 does **not** automatically change git revisions, restore backups, stop containers, or modify production state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  evaluateRollbackRestoreReadiness,
} from "../../../apps/api/src/services/rollbackRestoreReadiness";

describe("Milestone 25.6 rollback / restore readiness", () => {
  it("passes when required files and directories are available",()=> {
    const root=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-root-",
        ),
      );

    const data=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-data-",
        ),
      );

    const backup=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-backup-",
        ),
      );

    fs.mkdirSync(
      path.join(
        root,
        "scripts",
      ),
      {
        recursive:
          true,
      },
    );

    fs.writeFileSync(
      path.join(
        root,
        "docker-compose.yml",
      ),
      "services: {}",
    );

    fs.writeFileSync(
      path.join(
        root,
        "scripts/release-smoke-test.sh",
      ),
      "#!/bin/sh",
    );

    expect(
      evaluateRollbackRestoreReadiness({
        root,
        dataDir:
          data,
        backupDir:
          backup,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("fails without persistent data directory",()=> {
    const root=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.6-root-",
        ),
      );

    expect(
      evaluateRollbackRestoreReadiness({
        root,
        dataDir:
          null,
        backupDir:
          null,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("provides rollback readiness API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/rollback-restore-readiness"',
    );

    expect(route).toContain(
      "evaluateRollbackRestoreReadiness",
    );
  });

  it("provides host rollback preflight",()=> {
    const script=
      fs.readFileSync(
        new URL(
          "../../../scripts/release-rollback-preflight.sh",
          import.meta.url,
        ),
        "utf8",
      );

    expect(script).toContain(
      "git rev-parse --verify HEAD",
    );

    expect(script).toContain(
      "Rollback preflight PASSED.",
    );

    expect(script).toContain(
      "does not perform a rollback",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.6 installed"
echo "============================================================"
echo "Added:"
echo "  - rollback/restore readiness API"
echo "  - persistent data restore prerequisite checks"
echo "  - backup directory validation"
echo "  - host rollback preflight script"
echo "  - git revision verification"
echo "  - no automatic rollback execution"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  bash scripts/release-rollback-preflight.sh"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 25.7 - Release Artifact / Changelog Generation"
