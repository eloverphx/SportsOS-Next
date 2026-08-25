#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.1-release-readiness-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastReleaseReadiness.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/broadcast-release-readiness-25.1.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "docker-compose.yml" \
  "apps/api/Dockerfile" \
  "apps/dashboard/Dockerfile" \
  "docs/MILESTONE-24-BROADCAST-RESILIENCE-ACCEPTANCE.md" \
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
export type ReleaseReadinessCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type ReleaseReadinessInput = {
  env: Record<string, string | undefined>;
  composeSource: string;
  apiDockerfile: string;
  dashboardDockerfile: string;
};

export type ReleaseReadinessResult = {
  ready: boolean;
  checks: ReleaseReadinessCheck[];
};

const REQUIRED_ENV = [
  "SPORTSOS_DASHBOARD_URL",
  "SPORTSOS_API_URL",
  "MYSQL_DATABASE",
  "MYSQL_USER",
  "MYSQL_PASSWORD",
  "JWT_SECRET",
  "MINIO_ROOT_USER",
  "MINIO_ROOT_PASSWORD",
] as const;

export function evaluateBroadcastReleaseReadiness(
  input: ReleaseReadinessInput,
): ReleaseReadinessResult {
  const checks: ReleaseReadinessCheck[] = [];

  for (const name of REQUIRED_ENV) {
    const value =
      input.env[name]?.trim();

    checks.push({
      id:
        `env:${name}`,
      ok:
        Boolean(
          value,
        ),
      required:
        true,
      message:
        value
          ? `${name} is configured.`
          : `${name} is missing.`,
    });
  }

  checks.push({
    id:
      "compose:api-port",
    ok:
      input.composeSource.includes(
        '"4001:4001"',
      ),
    required:
      true,
    message:
      "API must publish port 4001.",
  });

  checks.push({
    id:
      "compose:dashboard-port",
    ok:
      input.composeSource.includes(
        '"4000:4000"',
      ),
    required:
      true,
    message:
      "Dashboard must publish port 4000.",
  });

  checks.push({
    id:
      "compose:persistent-data",
    ok:
      input.composeSource.includes(
        "SPORTSOS_DATA_DIR: /app/data",
      ) &&
      input.composeSource.includes(
        "/mnt/user/appdata/SportsOS-Next/data:/app/data",
      ),
    required:
      true,
    message:
      "API persistent data mount must be configured.",
  });

  checks.push({
    id:
      "compose:api-healthcheck",
    ok:
      input.composeSource.includes(
        "fetch('http://localhost:4001/health')",
      ),
    required:
      true,
    message:
      "API healthcheck must target /health on port 4001.",
  });

  checks.push({
    id:
      "compose:dashboard-depends-api-health",
    ok:
      input.composeSource.includes(
        "api: { condition: service_healthy }",
      ),
    required:
      true,
    message:
      "Dashboard must wait for healthy API.",
  });

  checks.push({
    id:
      "image:api-production",
    ok:
      input.apiDockerfile.includes(
        "NODE_ENV=production",
      ) ||
      input.apiDockerfile.includes(
        "NODE_ENV production",
      ),
    required:
      true,
    message:
      "API runtime image must run in production mode.",
  });

  checks.push({
    id:
      "image:dashboard-production",
    ok:
      input.dashboardDockerfile.includes(
        "NODE_ENV=production",
      ) ||
      input.dashboardDockerfile.includes(
        "NODE_ENV production",
      ),
    required:
      true,
    message:
      "Dashboard runtime image must run in production mode.",
  });

  checks.push({
    id:
      "safety:no-placeholder-jwt",
    ok:
      input.env.JWT_SECRET?.trim() !==
      "replace-with-at-least-32-random-characters",
    required:
      true,
    message:
      "JWT secret must not use the development placeholder.",
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
    checks,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  evaluateBroadcastReleaseReadiness,
} from "../services/broadcastReleaseReadiness.js";`;

if(!s.includes("evaluateBroadcastReleaseReadiness")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/release-readiness"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/operations-summary",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("Broadcast operations route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/release-readiness",
    async () => {
      const fs =
        await import(
          "node:fs",
        );

      const path =
        await import(
          "node:path",
        );

      const root =
        process.cwd();

      const composeSource =
        fs.readFileSync(
          path.resolve(
            root,
            "docker-compose.yml",
          ),
          "utf8",
        );

      const apiDockerfile =
        fs.readFileSync(
          path.resolve(
            root,
            "apps/api/Dockerfile",
          ),
          "utf8",
        );

      const dashboardDockerfile =
        fs.readFileSync(
          path.resolve(
            root,
            "apps/dashboard/Dockerfile",
          ),
          "utf8",
        );

      return {
        success: true,
        data:
          evaluateBroadcastReleaseReadiness({
            env:
              process.env,
            composeSource,
            apiDockerfile,
            dashboardDockerfile,
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
# SportsOS Broadcast Release Readiness

## Milestone 25.1 — Release-readiness foundation

Milestone 25 begins deployment and release hardening.

The release-readiness evaluator verifies that a production deployment has the
minimum required configuration before SportsOS is considered deployable.

Checks include:

- required environment variables
- API port 4001
- dashboard port 4000
- persistent API data mount
- API healthcheck
- dashboard dependency on healthy API
- API production runtime image
- dashboard production runtime image
- non-placeholder JWT secret

API:

```text
GET /broadcast-coordinator/release-readiness
```

The endpoint returns:

```text
ready
checks[]
```

Release readiness is read-only. It does not modify Docker, environment files,
secrets, containers, or broadcast state.

## Milestone 25 sequence

25.1 Release-readiness foundation  
25.2 Deployment manifest / version metadata  
25.3 Database and persistent-data migration readiness  
25.4 Secret and environment validation  
25.5 Health / smoke-test command bundle  
25.6 Rollback and restore readiness  
25.7 Release artifact / changelog generation  
25.8 Preflight deployment dashboard  
25.9 Staging-to-production acceptance rehearsal  
25.10 Deployment / release readiness closeout
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";

import {
  evaluateBroadcastReleaseReadiness,
} from "../../../apps/api/src/services/broadcastReleaseReadiness";

describe("Milestone 25.1 release-readiness foundation", () => {
  const env = {
    SPORTSOS_DASHBOARD_URL:
      "http://192.168.5.3:4000",
    SPORTSOS_API_URL:
      "http://192.168.5.3:4001",
    MYSQL_DATABASE:
      "sportsos",
    MYSQL_USER:
      "sportsos",
    MYSQL_PASSWORD:
      "secret",
    JWT_SECRET:
      "a-real-secret-value",
    MINIO_ROOT_USER:
      "sportsos",
    MINIO_ROOT_PASSWORD:
      "secret",
  };

  const composeSource = `
  api:
    environment:
      SPORTSOS_DATA_DIR: /app/data
    volumes:
      - /mnt/user/appdata/SportsOS-Next/data:/app/data
    ports:
      - "4001:4001"
    healthcheck:
      test:
        - "fetch('http://localhost:4001/health')"
  dashboard:
    ports:
      - "4000:4000"
    depends_on:
      api: { condition: service_healthy }
`;

  it("marks complete production configuration ready",()=> {
    const result=
      evaluateBroadcastReleaseReadiness({
        env,
        composeSource,
        apiDockerfile:
          "ENV NODE_ENV=production",
        dashboardDockerfile:
          "ENV NODE_ENV=production",
      });

    expect(
      result.ready,
    ).toBe(
      true,
    );
  });

  it("fails when required env is missing",()=> {
    const result=
      evaluateBroadcastReleaseReadiness({
        env: {
          ...env,
          MYSQL_PASSWORD:
            "",
        },
        composeSource,
        apiDockerfile:
          "ENV NODE_ENV=production",
        dashboardDockerfile:
          "ENV NODE_ENV=production",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );

    expect(
      result.checks.some(
        (check) =>
          check.id ===
            "env:MYSQL_PASSWORD" &&
          !check.ok,
      ),
    ).toBe(
      true,
    );
  });

  it("fails when persistent data mount is absent",()=> {
    const result=
      evaluateBroadcastReleaseReadiness({
        env,
        composeSource:
          composeSource.replace(
            "/mnt/user/appdata/SportsOS-Next/data:/app/data",
            "",
          ),
        apiDockerfile:
          "ENV NODE_ENV=production",
        dashboardDockerfile:
          "ENV NODE_ENV=production",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("fails placeholder JWT secret",()=> {
    const result=
      evaluateBroadcastReleaseReadiness({
        env: {
          ...env,
          JWT_SECRET:
            "replace-with-at-least-32-random-characters",
        },
        composeSource,
        apiDockerfile:
          "ENV NODE_ENV=production",
        dashboardDockerfile:
          "ENV NODE_ENV=production",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });

  it("requires healthy API dependency for dashboard",()=> {
    const result=
      evaluateBroadcastReleaseReadiness({
        env,
        composeSource:
          composeSource.replace(
            "api: { condition: service_healthy }",
            "",
          ),
        apiDockerfile:
          "ENV NODE_ENV=production",
        dashboardDockerfile:
          "ENV NODE_ENV=production",
      });

    expect(
      result.ready,
    ).toBe(
      false,
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.1 installed"
echo "============================================================"
echo "Added:"
echo "  - release-readiness evaluator"
echo "  - required environment validation"
echo "  - production image validation"
echo "  - persistent data mount validation"
echo "  - healthcheck/dependency validation"
echo "  - placeholder JWT safety check"
echo "  - release-readiness API"
echo "  - Milestone 25 roadmap"
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
echo "  Milestone 25.2 - Deployment Manifest / Version Metadata"
