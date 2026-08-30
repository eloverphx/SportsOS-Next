#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.8-security-telemetry-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/securityTelemetry.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
PAGE="apps/dashboard/app/broadcast/security/page.tsx"
TEST="packages/core/test/security-telemetry-26.8.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "apps/api/src/services/secretEnvironmentValidation.ts" \
  "apps/api/src/services/secretSourceHardening.ts" \
  "apps/api/src/services/sessionInvalidationReadiness.ts" \
  "apps/api/src/services/credentialRotationReadiness.ts" \
  "$ROUTE" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$PAGE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$PAGE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  evaluateCredentialRotationReadiness,
} from "./credentialRotationReadiness.js";

import {
  validateSecretEnvironment,
} from "./secretEnvironmentValidation.js";

import {
  evaluateSecretSourceHardening,
} from "./secretSourceHardening.js";

import {
  evaluateSessionInvalidationReadiness,
} from "./sessionInvalidationReadiness.js";

export type SecurityTelemetryInput = {
  root: string;
  env: Record<string, string | undefined>;
  rollbackReady: boolean;
  dataMigrationReady: boolean;
};

export type SecurityTelemetryResult = {
  ready: boolean;
  sections: {
    credentialRotation: ReturnType<
      typeof evaluateCredentialRotationReadiness
    >;
    secretEnvironment: ReturnType<
      typeof validateSecretEnvironment
    >;
    secretSource: ReturnType<
      typeof evaluateSecretSourceHardening
    >;
    sessionInvalidation: ReturnType<
      typeof evaluateSessionInvalidationReadiness
    >;
  };
  blockers: string[];
};

export function evaluateSecurityTelemetry(
  input: SecurityTelemetryInput,
): SecurityTelemetryResult {
  const credentialRotation =
    evaluateCredentialRotationReadiness({
      env:
        input.env,
      rollbackReady:
        input.rollbackReady,
      dataMigrationReady:
        input.dataMigrationReady,
    });

  const secretEnvironment =
    validateSecretEnvironment(
      input.env,
    );

  const secretSource =
    evaluateSecretSourceHardening({
      root:
        input.root,
    });

  const sessionInvalidation =
    evaluateSessionInvalidationReadiness(
      input.env,
    );

  const sections = {
    credentialRotation,
    secretEnvironment,
    secretSource,
    sessionInvalidation,
  };

  const blockers =
    Object.entries(
      sections,
    ).flatMap(
      ([
        sectionName,
        section,
      ]) =>
        section.checks
          .filter(
            (check) =>
              check.required &&
              !check.ok,
          )
          .map(
            (check) =>
              `${sectionName}:${check.id}`,
          ),
    );

  return {
    ready:
      blockers.length ===
      0,
    sections,
    blockers,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateSecurityTelemetry,
} from "../services/securityTelemetry.js";`;

if(!s.includes("evaluateSecurityTelemetry")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/security-telemetry"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/session-invalidation-readiness",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("26.6 session invalidation route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/security-telemetry",
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
          evaluateSecurityTelemetry({
            root:
              process.cwd(),
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

cat > "$PAGE" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type Check = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

type Section = {
  ready: boolean;
  checks: Check[];
};

type SecurityTelemetry = {
  ready: boolean;
  blockers: string[];
  sections: {
    credentialRotation: Section;
    secretEnvironment: Section;
    secretSource: Section;
    sessionInvalidation: Section;
  };
};

export default function SecurityTelemetryPage() {
  const [data, setData] =
    useState<SecurityTelemetry | null>(null);

  const [error, setError] =
    useState<string | null>(null);

  const load =
    useCallback(
      async () => {
        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/security-telemetry`,
              {
                cache:
                  "no-store",
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Unable to load security telemetry.",
            );
          }

          setData(
            json?.data ??
            null,
          );
          setError(null);
        } catch (err) {
          setError(
            err instanceof Error
              ? err.message
              : "Unable to load security telemetry.",
          );
        }
      },
      [],
    );

  useEffect(() => {
    void load();
  }, [load]);

  const sections = data
    ? [
        [
          "Credential Rotation",
          data.sections.credentialRotation,
        ],
        [
          "Secret / Environment",
          data.sections.secretEnvironment,
        ],
        [
          "Secret Source",
          data.sections.secretSource,
        ],
        [
          "Session Invalidation",
          data.sections.sessionInvalidation,
        ],
      ] as const
    : [];

  return (
    <main className="mx-auto max-w-7xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <a
            href="/broadcast/deployment"
            className="text-xs text-slate-500"
          >
            ← Deployment Preflight
          </a>

          <h1 className="mt-2 text-2xl font-bold">
            Security Telemetry
          </h1>

          <p className="mt-1 text-sm text-slate-500">
            Production credential, secret-source, session, and hardening readiness.
          </p>
        </div>

        <button
          type="button"
          onClick={() =>
            void load()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm"
        >
          Refresh Security
        </button>
      </div>

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <div className="text-xs text-slate-500">
          Security Gate
        </div>

        <div className="mt-1 text-2xl font-bold">
          {data?.ready
            ? "READY"
            : "BLOCKED"}
        </div>

        <div className="mt-3 text-xs text-slate-500">
          Required blockers:{" "}
          {data?.blockers?.length
            ? data.blockers.join(", ")
            : "none"}
        </div>
      </section>

      {error && (
        <div className="mt-4 rounded-xl border border-red-900/40 p-4 text-sm text-red-300">
          {error}
        </div>
      )}

      <section className="mt-6 grid gap-4 lg:grid-cols-2">
        {sections.map(
          ([title, section]) => (
            <div
              key={title}
              className="rounded-xl border border-slate-800 p-5"
            >
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-lg font-semibold">
                  {title}
                </h2>

                <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
                  {section.ready
                    ? "READY"
                    : "BLOCKED"}
                </span>
              </div>

              <div className="mt-4 space-y-2">
                {section.checks.map(
                  (check) => (
                    <div
                      key={check.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-xs font-semibold">
                          {check.id}
                        </span>

                        <span className="text-xs">
                          {check.ok
                            ? "PASS"
                            : "FAIL"}
                        </span>
                      </div>

                      <div className="mt-1 text-xs text-slate-500">
                        {check.message}
                      </div>
                    </div>
                  ),
                )}
              </div>
            </div>
          ),
        )}
      </section>
    </main>
  );
}
EOF

cat >> "$DOC" <<'EOF'

## Milestone 26.8 — Security telemetry / operator visibility

SportsOS now exposes a consolidated security telemetry endpoint:

```text
GET /broadcast-coordinator/security-telemetry
```

and dashboard:

```text
/broadcast/security
```

The security gate consolidates credential rotation readiness, secret/environment validation, secret-source hardening, and session/token invalidation readiness.

The response includes `ready`, `sections`, and `blockers[]`.

The dashboard is read-only and does not rotate credentials, invalidate sessions, or modify security configuration.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.8 security telemetry / operator visibility", () => {
  it("provides security telemetry API and dashboard",()=> {
    const route =
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/security-telemetry"',
    );

    expect(page).toContain(
      "Security Telemetry",
    );

    expect(page).toContain(
      "Security Gate",
    );

    expect(page).toContain(
      "BLOCKED",
    );
  });

  it("keeps dashboard read-only",()=> {
    const page =
      fs.readFileSync(
        new URL(
          "../../../apps/dashboard/app/broadcast/security/page.tsx",
          import.meta.url,
        ),
        "utf8",
      );

    expect(page).not.toContain(
      'method: "POST"',
    );

    expect(page).not.toContain(
      'method: "DELETE"',
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.8 installed"
echo "============================================================"
echo "Added:"
echo "  - consolidated security telemetry service"
echo "  - security blockers list"
echo "  - /broadcast-coordinator/security-telemetry"
echo "  - /broadcast/security"
echo "  - credential/secret/session visibility"
echo "  - read-only security gate"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  curl -fsS http://127.0.0.1:4001/broadcast-coordinator/security-telemetry"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 26.9 - Security Regression / Attack-Surface Tests"
