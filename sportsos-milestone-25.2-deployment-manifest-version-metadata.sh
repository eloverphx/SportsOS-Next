#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.2-deployment-manifest-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/deploymentManifest.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
TEST="packages/core/test/deployment-manifest-25.2.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "package.json" \
  "apps/api/package.json" \
  "apps/dashboard/package.json" \
  "apps/api/src/services/broadcastReleaseReadiness.ts" \
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
import {
  execFileSync,
} from "node:child_process";

import fs from "node:fs";
import path from "node:path";

export type DeploymentManifest = {
  generatedAt: string;
  repository: {
    commit: string | null;
    branch: string | null;
    tag: string | null;
    dirty: boolean | null;
  };
  versions: {
    root: string | null;
    api: string | null;
    dashboard: string | null;
    node: string;
  };
  runtime: {
    nodeEnv: string | null;
    port: string | null;
    host: string | null;
    dataDir: string | null;
  };
};

function readJsonVersion(
  file: string,
): string | null {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          file,
          "utf8",
        ),
      ) as {
        version?: string;
      };

    return parsed.version ??
      null;
  } catch {
    return null;
  }
}

function runGit(
  args: string[],
): string | null {
  try {
    return execFileSync(
      "git",
      args,
      {
        cwd:
          process.cwd(),
        encoding:
          "utf8",
        stdio: [
          "ignore",
          "pipe",
          "ignore",
        ],
      },
    )
      .trim() ||
      null;
  } catch {
    return null;
  }
}

export function createDeploymentManifest(): DeploymentManifest {
  const root =
    process.cwd();

  const commit =
    runGit([
      "rev-parse",
      "HEAD",
    ]);

  const branch =
    runGit([
      "branch",
      "--show-current",
    ]);

  const tag =
    runGit([
      "describe",
      "--tags",
      "--exact-match",
      "HEAD",
    ]);

  const status =
    runGit([
      "status",
      "--porcelain",
    ]);

  return {
    generatedAt:
      new Date().toISOString(),
    repository: {
      commit,
      branch,
      tag,
      dirty:
        status === null
          ? null
          : status.length >
            0,
    },
    versions: {
      root:
        readJsonVersion(
          path.resolve(
            root,
            "package.json",
          ),
        ),
      api:
        readJsonVersion(
          path.resolve(
            root,
            "apps/api/package.json",
          ),
        ),
      dashboard:
        readJsonVersion(
          path.resolve(
            root,
            "apps/dashboard/package.json",
          ),
        ),
      node:
        process.version,
    },
    runtime: {
      nodeEnv:
        process.env.NODE_ENV ??
        null,
      port:
        process.env.PORT ??
        null,
      host:
        process.env.HOST ??
        null,
      dataDir:
        process.env.SPORTSOS_DATA_DIR ??
        null,
    },
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  createDeploymentManifest,
} from "../services/deploymentManifest.js";`;

if(!s.includes("createDeploymentManifest")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/deployment-manifest"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/release-readiness",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("25.1 release-readiness route missing.");

  const route=`  app.get(
    "/broadcast-coordinator/deployment-manifest",
    async () => {
      return {
        success: true,
        data:
          createDeploymentManifest(),
      };
    },
  );

`;

  s=s.slice(0,i)+route+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 25.2 — Deployment manifest / version metadata

SportsOS now exposes a deployment manifest for release identification and auditing.

API:

```text
GET /broadcast-coordinator/deployment-manifest
```

The manifest includes:

```text
generatedAt

repository:
  commit
  branch
  tag
  dirty

versions:
  root
  api
  dashboard
  node

runtime:
  NODE_ENV
  PORT
  HOST
  SPORTSOS_DATA_DIR
```

Git metadata is best-effort. If the production image does not contain `.git`, repository fields return `null` rather than failing the API.

The manifest is read-only and does not alter release state or deployment configuration.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  createDeploymentManifest,
} from "../../../apps/api/src/services/deploymentManifest";

describe("Milestone 25.2 deployment manifest / version metadata", () => {
  it("creates version and runtime metadata",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.generatedAt,
    ).toBeTruthy();

    expect(
      manifest.versions.node,
    ).toBe(
      process.version,
    );

    expect(
      manifest.versions.root,
    ).toBeTruthy();
  });

  it("includes repository metadata shape",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.repository,
    ).toHaveProperty(
      "commit",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "branch",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "tag",
    );

    expect(
      manifest.repository,
    ).toHaveProperty(
      "dirty",
    );
  });

  it("includes deployment runtime fields",()=> {
    const manifest=
      createDeploymentManifest();

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "nodeEnv",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "port",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "host",
    );

    expect(
      manifest.runtime,
    ).toHaveProperty(
      "dataDir",
    );
  });

  it("provides deployment-manifest API",()=> {
    const route=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(route).toContain(
      '"/broadcast-coordinator/deployment-manifest"',
    );

    expect(route).toContain(
      "createDeploymentManifest",
    );
  });

  it("does not write deployment state",()=> {
    const service=
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/services/deploymentManifest.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(service).not.toContain(
      "writeFileSync",
    );

    expect(service).not.toContain(
      "renameSync",
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.2 installed"
echo "============================================================"
echo "Added:"
echo "  - deployment manifest service"
echo "  - git commit/branch/tag metadata"
echo "  - dirty-working-tree visibility"
echo "  - root/api/dashboard version metadata"
echo "  - runtime environment metadata"
echo "  - deployment-manifest API"
echo "  - read-only manifest generation"
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
echo "  Milestone 25.3 - Database / Persistent Data Migration Readiness"
