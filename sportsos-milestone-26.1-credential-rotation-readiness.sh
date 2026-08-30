#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.1-credential-rotation-readiness-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/credentialRotationReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/credential-rotation-readiness-26.1.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
  "apps/api/src/services/rollbackRestoreReadiness.ts" \
  "docs/MILESTONE-25-DEPLOYMENT-RELEASE-READINESS-ACCEPTANCE.md" \
  "$ROUTE"
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

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")" "$(dirname "$DOC")"

cat > "$SERVICE" <<'EOF'
export type CredentialRotationTarget =
  | "JWT_SECRET"
  | "MYSQL_PASSWORD"
  | "MINIO_SECRET_KEY";

export type CredentialRotationCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type CredentialRotationReadinessInput = {
  env: Record<string, string | undefined>;
  rollbackReady: boolean;
  dataMigrationReady: boolean;
};

export type CredentialRotationReadinessResult = {
  ready: boolean;
  targets: CredentialRotationTarget[];
  checks: CredentialRotationCheck[];
};

const TARGETS: CredentialRotationTarget[] = [
  "JWT_SECRET",
  "MYSQL_PASSWORD",
  "MINIO_SECRET_KEY",
];

function configured(
  value: string | undefined,
): boolean {
  return Boolean(
    value?.trim(),
  );
}

export function evaluateCredentialRotationReadiness(
  input: CredentialRotationReadinessInput,
): CredentialRotationReadinessResult {
  const checks: CredentialRotationCheck[] = [];

  checks.push({
    id: "rollback:ready",
    ok: input.rollbackReady,
    required: true,
    message:
      input.rollbackReady
        ? "Rollback / restore prerequisites are ready."
        : "Rollback / restore prerequisites are not ready.",
  });

  checks.push({
    id: "migration:ready",
    ok: input.dataMigrationReady,
    required: true,
    message:
      input.dataMigrationReady
        ? "Database and persistent-data readiness checks pass."
        : "Database or persistent-data readiness checks are not ready.",
  });

  for (const target of TARGETS) {
    checks.push({
      id: `current:${target}`,
      ok: configured(input.env[target]),
      required: true,
      message:
        configured(input.env[target])
          ? `${target} is currently configured.`
          : `${target} is missing.`,
    });
  }

  checks.push({
    id: "mysql:dedicated-user",
    ok:
      Boolean(
        input.env.MYSQL_USER?.trim(),
      ) &&
      input.env.MYSQL_USER?.trim() !==
        "root",
    required: true,
    message:
      "MySQL credential rotation requires a dedicated non-root SportsOS user.",
  });

  checks.push({
    id: "minio:access-key-present",
    ok:
      configured(
        input.env.MINIO_ACCESS_KEY,
      ),
    required: true,
    message:
      "MinIO credential rotation requires the current access key.",
  });

  checks.push({
    id: "runtime:data-dir",
    ok:
      input.env.SPORTSOS_DATA_DIR ===
      "/app/data",
    required: true,
    message:
      "Persistent SportsOS data must be mounted at /app/data before credential rotation.",
  });

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
    targets:
      [...TARGETS],
    checks,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateCredentialRotationReadiness,
} from "../services/credentialRotationReadiness.js";`;

if(!s.includes("evaluateCredentialRotationReadiness")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/credential-rotation-readiness"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/rollback-restore-readiness",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("25.6 rollback readiness route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/credential-rotation-readiness",
    async () => {
      const rollback =
        evaluateRollbackRestoreReadiness({
          root:
            process.cwd(),
          dataDir:
            process.env.SPORTSOS_DATA_DIR ??
            null,
          backupDir:
            process.env.SPORTSOS_BACKUP_DIR ??
            "/app/data/backups",
        });

      let mysqlReachable =
        false;

      try {
        const mysql =
          await import(
            "mysql2/promise",
          );

        const connection =
          await mysql.default.createConnection({
            host:
              process.env.MYSQL_HOST ??
              "mysql",
            port:
              Number(
                process.env.MYSQL_PORT ??
                3306,
              ),
            database:
              process.env.MYSQL_DATABASE,
            user:
              process.env.MYSQL_USER,
            password:
              process.env.MYSQL_PASSWORD,
          });

        try {
          await connection.query(
            "SELECT 1",
          );

          mysqlReachable =
            true;
        } finally {
          await connection.end();
        }
      } catch {
        mysqlReachable =
          false;
      }

      const migration =
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
        });

      return {
        success: true,
        data:
          evaluateCredentialRotationReadiness({
            env:
              process.env,
            rollbackReady:
              rollback.ready,
            dataMigrationReady:
              migration.ready,
          }),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat > "$DOC" <<'EOF'
# SportsOS Production Security Hardening

## Milestone 26.1 — Credential rotation readiness

Milestone 26 begins production credential and security hardening.

The first step is a read-only credential-rotation readiness gate.

Rotation targets:

```text
JWT_SECRET
MYSQL_PASSWORD
MINIO_SECRET_KEY
```

API:

```text
GET /broadcast-coordinator/credential-rotation-readiness
```

Required prerequisites include:

- rollback / restore readiness
- database and persistent-data readiness
- current JWT, MySQL, and MinIO secrets configured
- dedicated non-root MySQL user
- current MinIO access key present
- persistent SportsOS data mounted at `/app/data`

The readiness endpoint does not change credentials.

## Milestone 26 sequence

26.1 Credential rotation readiness  
26.2 JWT secret rotation workflow  
26.3 MySQL credential rotation workflow  
26.4 MinIO credential rotation workflow  
26.5 Secret-file / environment-source hardening  
26.6 Session/token invalidation readiness  
26.7 Security headers / transport hardening  
26.8 Security telemetry / operator visibility  
26.9 Security regression / attack-surface tests  
26.10 Production security acceptance / closeout
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateCredentialRotationReadiness,
} from "../../../apps/api/src/services/credentialRotationReadiness";

describe("Milestone 26.1 credential rotation readiness", () => {
  const env = {
    JWT_SECRET:
      "configured-jwt",
    MYSQL_PASSWORD:
      "configured-mysql",
    MINIO_SECRET_KEY:
      "configured-minio",
    MYSQL_USER:
      "sportsos",
    MINIO_ACCESS_KEY:
      "sportsos",
    SPORTSOS_DATA_DIR:
      "/app/data",
  };

  it("passes when rollback, data, and current credentials are ready",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("requires rollback readiness",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          false,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("requires data migration readiness",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env,
        rollbackReady:
          true,
        dataMigrationReady:
          false,
      }).ready,
    ).toBe(
      false,
    );
  });

  it("requires all current rotation targets",()=> {
    const result=
      evaluateCredentialRotationReadiness({
        env: {
          ...env,
          JWT_SECRET:
            "",
        },
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );

    expect(
      result.targets,
    ).toEqual([
      "JWT_SECRET",
      "MYSQL_PASSWORD",
      "MINIO_SECRET_KEY",
    ]);
  });

  it("requires non-root mysql user",()=> {
    expect(
      evaluateCredentialRotationReadiness({
        env: {
          ...env,
          MYSQL_USER:
            "root",
        },
        rollbackReady:
          true,
        dataMigrationReady:
          true,
      }).ready,
    ).toBe(
      false,
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.1 installed"
echo "============================================================"
echo "Added:"
echo "  - credential rotation readiness evaluator"
echo "  - JWT/MySQL/MinIO rotation target inventory"
echo "  - rollback prerequisite gate"
echo "  - data migration prerequisite gate"
echo "  - dedicated MySQL user requirement"
echo "  - persistent data mount requirement"
echo "  - read-only readiness API"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  curl -fsS http://127.0.0.1:4001/broadcast-coordinator/credential-rotation-readiness"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 26.2 - JWT Secret Rotation Workflow"
