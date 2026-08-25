#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25-release-runtime-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastReleaseReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-release-readiness-25.1.test.ts"
DIAG="scripts/release-readiness-diagnostics.sh"

for required in ".git" "$SERVICE" "$ROUTE" "scripts/release-smoke-test.sh"; do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$TEST" "$DIAG"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")" "$(dirname "$DIAG")"

cat > "$SERVICE" <<'EOF'
export type ReleaseReadinessCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type ReleaseReadinessInput = {
  env: Record<string, string | undefined>;
};

export type ReleaseReadinessResult = {
  ready: boolean;
  checks: ReleaseReadinessCheck[];
};

function configured(
  value: string | undefined,
): boolean {
  return Boolean(
    value?.trim(),
  );
}

export function evaluateBroadcastReleaseReadiness(
  input: ReleaseReadinessInput,
): ReleaseReadinessResult {
  const env =
    input.env;

  const checks:
    ReleaseReadinessCheck[] =
    [];

  checks.push({
    id:
      "runtime:node-env",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV === "production"
        ? "API is running in production mode."
        : "API must run with NODE_ENV=production.",
  });

  checks.push({
    id:
      "runtime:api-port",
    ok:
      env.PORT ===
      "4001",
    required:
      true,
    message:
      env.PORT === "4001"
        ? "API runtime port is 4001."
        : "API runtime PORT must be 4001.",
  });

  checks.push({
    id:
      "runtime:host",
    ok:
      env.HOST ===
      "0.0.0.0",
    required:
      true,
    message:
      env.HOST === "0.0.0.0"
        ? "API binds to 0.0.0.0."
        : "API HOST must be 0.0.0.0.",
  });

  checks.push({
    id:
      "runtime:data-dir",
    ok:
      env.SPORTSOS_DATA_DIR ===
      "/app/data",
    required:
      true,
    message:
      env.SPORTSOS_DATA_DIR === "/app/data"
        ? "Persistent data directory is /app/data."
        : "SPORTSOS_DATA_DIR must be /app/data.",
  });

  checks.push({
    id:
      "runtime:dashboard-origin",
    ok:
      configured(
        env.DASHBOARD_ORIGIN,
      ),
    required:
      true,
    message:
      configured(env.DASHBOARD_ORIGIN)
        ? "Dashboard origin is configured."
        : "DASHBOARD_ORIGIN is missing.",
  });

  checks.push({
    id:
      "runtime:public-api-url",
    ok:
      configured(
        env.PUBLIC_API_URL,
      ),
    required:
      true,
    message:
      configured(env.PUBLIC_API_URL)
        ? "Public API URL is configured."
        : "PUBLIC_API_URL is missing.",
  });

  for (
    const name
    of [
      "MYSQL_HOST",
      "MYSQL_DATABASE",
      "MYSQL_USER",
      "MYSQL_PASSWORD",
      "MINIO_ENDPOINT",
      "MINIO_ACCESS_KEY",
      "MINIO_SECRET_KEY",
      "JWT_SECRET",
    ]
  ) {
    checks.push({
      id:
        `runtime:${name}`,
      ok:
        configured(
          env[name],
        ),
      required:
        true,
      message:
        configured(env[name])
          ? `${name} is configured.`
          : `${name} is missing.`,
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
const file="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(file,"utf8");

const start = s.indexOf(
`  app.get(
    "/broadcast-coordinator/release-readiness",`
);

if(start < 0) {
  throw new Error("25.1 release-readiness route not found.");
}

let depth = 0;
let i = start;
let end = -1;
let began = false;

for (; i < s.length; i++) {
  if (s[i] === "(") {
    depth++;
    began = true;
  } else if (s[i] === ")") {
    depth--;
  }

  if (
    began &&
    depth === 0 &&
    s.slice(i, i + 2) === ");"
  ) {
    end = i + 2;
    break;
  }
}

if(end < 0) {
  throw new Error("Unable to locate end of release-readiness route.");
}

const replacement = `  app.get(
    "/broadcast-coordinator/release-readiness",
    async () => {
      return {
        success: true,
        data:
          evaluateBroadcastReleaseReadiness({
            env:
              process.env,
          }),
      };
    },
  );`;

s =
  s.slice(0,start) +
  replacement +
  s.slice(end);

fs.writeFileSync(file,s);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateBroadcastReleaseReadiness,
} from "../../../apps/api/src/services/broadcastReleaseReadiness";

describe("Milestone 25.1 runtime release readiness", () => {
  const good = {
    NODE_ENV:
      "production",
    PORT:
      "4001",
    HOST:
      "0.0.0.0",
    SPORTSOS_DATA_DIR:
      "/app/data",
    DASHBOARD_ORIGIN:
      "http://192.168.5.3:4000",
    PUBLIC_API_URL:
      "http://192.168.5.3:4001",
    MYSQL_HOST:
      "mysql",
    MYSQL_DATABASE:
      "sportsos",
    MYSQL_USER:
      "sportsos",
    MYSQL_PASSWORD:
      "configured",
    MINIO_ENDPOINT:
      "minio",
    MINIO_ACCESS_KEY:
      "sportsos",
    MINIO_SECRET_KEY:
      "configured",
    JWT_SECRET:
      "configured",
  };

  it("passes an actually configured production runtime",()=> {
    expect(
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      }).ready,
    ).toBe(
      true,
    );
  });

  it("requires persistent /app/data",()=> {
    expect(
      evaluateBroadcastReleaseReadiness({
        env: {
          ...good,
          SPORTSOS_DATA_DIR:
            undefined,
        },
      }).ready,
    ).toBe(
      false,
    );
  });

  it("uses runtime env names from the API container",()=> {
    const result =
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      });

    expect(
      result.checks.some(
        (check) =>
          check.id ===
            "runtime:dashboard-origin" &&
          check.ok,
      ),
    ).toBe(
      true,
    );

    expect(
      result.checks.some(
        (check) =>
          check.id ===
            "runtime:public-api-url" &&
          check.ok,
      ),
    ).toBe(
      true,
    );
  });

  it("does not require compose or Dockerfile source files at runtime",()=> {
    const result =
      evaluateBroadcastReleaseReadiness({
        env:
          good,
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });
});
EOF

cat > "$DIAG" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"

node - "$API_URL" <<'NODE'
const base = process.argv[2];

const endpoints = [
  [
    "Release readiness",
    "/broadcast-coordinator/release-readiness",
  ],
  [
    "Secret/environment validation",
    "/broadcast-coordinator/secret-environment-validation",
  ],
];

for (const [name, path] of endpoints) {
  try {
    const response =
      await fetch(
        `${base}${path}`,
      );

    const json =
      await response.json();

    console.log(`\n=== ${name} ===`);
    console.log(`HTTP ${response.status}`);

    for (
      const check
      of json?.data?.checks ??
      []
    ) {
      console.log(
        `${check.ok ? "PASS" : "FAIL"}  ${check.id}  ${check.message}`,
      );
    }
  } catch (error) {
    console.log(`\n=== ${name} ===`);
    console.log(
      `ERROR ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}
NODE
EOF

chmod +x "$DIAG"

echo "============================================================"
echo " SportsOS Milestone 25 runtime-readiness repair installed"
echo "============================================================"
echo "Fixed:"
echo "  - 25.1 no longer reads compose/Dockerfiles from runtime image"
echo "  - uses actual API runtime env names"
echo "  - DASHBOARD_ORIGIN / PUBLIC_API_URL recognized"
echo "  - SPORTSOS_DATA_DIR /app/data remains required"
echo "Added:"
echo "  - scripts/release-readiness-diagnostics.sh"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-readiness-diagnostics.sh"
echo "  bash scripts/release-smoke-test.sh"
