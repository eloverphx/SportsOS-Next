#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.3-data-migration-readiness-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/dataMigrationReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/data-migration-readiness-25.3.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "apps/api/src/plugins/mysql.ts" \
  "apps/api/src/services/broadcastOperatorNotes.ts" \
  "apps/api/src/services/broadcastRecoverySnapshotStore.ts" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type DataMigrationReadinessCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type DataMigrationReadinessInput = {
  dataDir:
    string | null;
  files:
    string[];
  mysqlReachable:
    boolean;
};

export type DataMigrationReadinessResult = {
  ready: boolean;
  checks:
    DataMigrationReadinessCheck[];
};

export function evaluateDataMigrationReadiness(
  input: DataMigrationReadinessInput,
): DataMigrationReadinessResult {
  const checks:
    DataMigrationReadinessCheck[] =
    [];

  checks.push({
    id:
      "mysql:reachable",
    ok:
      input.mysqlReachable,
    required:
      true,
    message:
      input.mysqlReachable
        ? "MySQL is reachable."
        : "MySQL is not reachable.",
  });

  const dataDir =
    input.dataDir?.trim() ??
    "";

  checks.push({
    id:
      "data-dir:configured",
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
    let writable =
      false;

    try {
      fs.mkdirSync(
        dataDir,
        {
          recursive: true,
        },
      );

      fs.accessSync(
        dataDir,
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
        "data-dir:rw",
      ok:
        writable,
      required:
        true,
      message:
        writable
          ? "Persistent data directory is readable and writable."
          : "Persistent data directory is not readable and writable.",
    });

    for (
      const file
      of input.files
    ) {
      const fullPath =
        path.join(
          dataDir,
          file,
        );

      if (
        !fs.existsSync(
          fullPath,
        )
      ) {
        checks.push({
          id:
            `store:${file}`,
          ok:
            true,
          required:
            false,
          message:
            `${file} does not exist yet; a new store can be created.`,
        });

        continue;
      }

      let valid =
        false;

      try {
        JSON.parse(
          fs.readFileSync(
            fullPath,
            "utf8",
          ),
        );

        valid =
          true;
      } catch {
        valid =
          false;
      }

      checks.push({
        id:
          `store:${file}`,
        ok:
          valid,
        required:
          true,
        message:
          valid
            ? `${file} is readable JSON.`
            : `${file} is unreadable or invalid JSON.`,
      });
    }
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
  evaluateDataMigrationReadiness,
} from "../services/dataMigrationReadiness.js";`;

if(!s.includes("evaluateDataMigrationReadiness")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/data-migration-readiness"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/deployment-manifest",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("25.2 deployment-manifest route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/data-migration-readiness",
    async () => {
      let mysqlReachable =
        false;

      try {
        await app.mysql.query(
          "SELECT 1",
        );

        mysqlReachable =
          true;
      } catch {
        mysqlReachable =
          false;
      }

      return {
        success: true,
        data:
          evaluateDataMigrationReadiness({
            dataDir:
              process.env.SPORTSOS_DATA_DIR ??
              null,
            mysqlReachable,
            files: [
              "broadcast-operator-notes.json",
              "broadcast-recovery-snapshots.json",
              "broadcast-session-profiles.json",
              "stream-destination-profiles.json",
              "encoder-sessions.json",
              "encoder-runtime-audit.json",
              "go-live-sessions.json",
              "go-live-audit.json",
              "broadcast-session-coordinator.json",
              "broadcast-coordinator-audit.json",
            ],
          }),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 25.3 — Database / persistent data migration readiness

SportsOS now checks deployment-time readiness for both MySQL and JSON-backed persistent stores.

API:

```text
GET /broadcast-coordinator/data-migration-readiness
```

Required checks:

```text
MySQL reachable
SPORTSOS_DATA_DIR configured
persistent data directory readable/writable
existing JSON stores parse successfully
```

A missing JSON store is not considered a failure because a new deployment may legitimately create it on first use.

Existing stores that are present but unreadable or invalid JSON fail readiness.

Checked persistent stores include operator notes, recovery snapshots, broadcast session profiles, stream destination profiles, encoder state/audit, go-live state/audit, and coordinator state/audit.

This endpoint does not mutate database schema or rewrite existing persistent stores.
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
  evaluateDataMigrationReadiness,
} from "../../../apps/api/src/services/dataMigrationReadiness";

describe("Milestone 25.3 database / persistent data migration readiness", () => {
  it("passes with reachable mysql and writable empty data directory",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "optional-store.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });

  it("fails when mysql is unavailable",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          false,
        files:
          [],
      }).ready,
    ).toBe(
      false,
    );
  });

  it("fails when data dir is missing",()=> {
    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          null,
        mysqlReachable:
          true,
        files:
          [],
      }).ready,
    ).toBe(
      false,
    );
  });

  it("allows absent optional store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "missing.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });

  it("fails invalid existing json store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    fs.writeFileSync(
      path.join(
        dir,
        "bad.json",
      ),
      "{not-json",
      "utf8",
    );

    const result=
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "bad.json",
        ],
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("passes valid existing json store",()=> {
    const dir=
      fs.mkdtempSync(
        path.join(
          os.tmpdir(),
          "sportsos-25.3-",
        ),
      );

    fs.writeFileSync(
      path.join(
        dir,
        "good.json",
      ),
      JSON.stringify({
        version:
          1,
      }),
      "utf8",
    );

    expect(
      evaluateDataMigrationReadiness({
        dataDir:
          dir,
        mysqlReachable:
          true,
        files: [
          "good.json",
        ],
      }).ready,
    ).toBe(
      true,
    );
  });

  it("provides migration-readiness API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/data-migration-readiness"',
    );

    expect(route).toContain(
      "SELECT 1",
    );

    expect(route).toContain(
      "evaluateDataMigrationReadiness",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.3 installed"
echo "============================================================"
echo "Added:"
echo "  - MySQL connectivity readiness"
echo "  - persistent data directory validation"
echo "  - JSON store parse validation"
echo "  - missing-store first-run tolerance"
echo "  - migration-readiness API"
echo "  - no schema/store mutation"
echo "  - Milestone 25.3 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  docker compose ps"
echo "  curl -fsS http://127.0.0.1:4001/health"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 25.4 - Secret / Environment Validation"
