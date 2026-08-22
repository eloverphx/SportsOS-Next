#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.9-incident-resolution-recovery-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAuthorization.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardControlIncidentResolution.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/incident-resolution-recovery-15.9.test.ts"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type ScoreboardControlIncidentStatus =
  | "OPEN"
  | "ACKNOWLEDGED"
  | "RESOLVED";

export type ScoreboardControlIncidentResolution = {
  auditId: string;
  status: ScoreboardControlIncidentStatus;
  note: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  updatedAt: string;
};

type Store = {
  version: 1;
  resolutions: ScoreboardControlIncidentResolution[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-control-incident-resolution.json",
  );

let store = loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.resolutions,
      )
    ) {
      throw new Error(
        "Invalid scoreboard control incident resolution store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      resolutions: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function getScoreboardControlIncidentResolution(
  auditId: string,
): ScoreboardControlIncidentResolution | null {
  return (
    store.resolutions.find(
      (item) =>
        item.auditId === auditId,
    ) ?? null
  );
}

export function setScoreboardControlIncidentResolution(input: {
  auditId: string;
  status: ScoreboardControlIncidentStatus;
  note?: string | null;
  actorUserId: string | null;
  actorRoles: string[];
}): ScoreboardControlIncidentResolution {
  const resolution: ScoreboardControlIncidentResolution = {
    auditId: input.auditId,
    status: input.status,
    note:
      input.note?.trim() ||
      null,
    actorUserId:
      input.actorUserId,
    actorRoles:
      [...input.actorRoles],
    updatedAt:
      new Date().toISOString(),
  };

  store.resolutions =
    store.resolutions.filter(
      (item) =>
        item.auditId !==
        input.auditId,
    );

  store.resolutions.push(
    resolution,
  );

  persistStore();

  return resolution;
}

export function listScoreboardControlIncidentResolutions():
  ScoreboardControlIncidentResolution[] {
  return [...store.resolutions]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}
EOF

node <<'NODE'
const fs = require("fs");

const routeFile =
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let route =
  fs.readFileSync(
    routeFile,
    "utf8",
  );

const importLine =
  'import { getScoreboardControlIncidentResolution, listScoreboardControlIncidentResolutions, setScoreboardControlIncidentResolution } from "../services/scoreboardControlIncidentResolution.js";';

if (!route.includes(importLine)) {
  const imports =
    route.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboardControlPolicy imports.",
    );
  }

  route =
    route.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !route.includes(
    "/scoreboard-control-incident-resolutions",
  )
) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    route.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate policy route registration.",
    );
  }

  const open =
    route.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate route function body.",
    );
  }

  const block = `
  app.get(
    "/scoreboard-control-incident-resolutions",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy read permission required.",
        });
      }

      return {
        success: true,
        data: {
          resolutions:
            listScoreboardControlIncidentResolutions(),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-incidents/:auditId",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const params =
        request.params as {
          auditId?: string;
        };

      const body =
        request.body as {
          status?:
            | "OPEN"
            | "ACKNOWLEDGED"
            | "RESOLVED";
          note?: string | null;
        };

      const auditId =
        params.auditId?.trim();

      if (!auditId) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident audit ID is required.",
        });
      }

      if (
        body.status !== "OPEN" &&
        body.status !== "ACKNOWLEDGED" &&
        body.status !== "RESOLVED"
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident status must be OPEN, ACKNOWLEDGED, or RESOLVED.",
        });
      }

      if (
        body.status === "RESOLVED" &&
        !body.note?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "A resolution note is required when resolving an incident.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      const previous =
        getScoreboardControlIncidentResolution(
          auditId,
        );

      const resolution =
        setScoreboardControlIncidentResolution({
          auditId,
          status:
            body.status,
          note:
            body.note,
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
        });

      return {
        success: true,
        data: {
          previous,
          resolution,
        },
      };
    },
  );

`;

  route =
    route.slice(
      0,
      open + 1,
    ) +
    block +
    route.slice(
      open + 1,
    );
}

fs.writeFileSync(
  routeFile,
  route,
);

const panelFile =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

const panel =
  fs.readFileSync(
    panelFile,
    "utf8",
  );

for (const required of [
  "IncidentResolution",
  "incidentResolutions",
  "updateIncidentResolution",
  "Acknowledge",
  "Resolve",
]) {
  if (!panel.includes(required)) {
    throw new Error(
      `15.9 UI hook missing: ${required}`,
    );
  }
}
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.9 incident-resolution recovery", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlIncidentResolution.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores the persistent incident-resolution service", () => {
    expect(service).toContain(
      "scoreboard-control-incident-resolution.json",
    );

    expect(service).toContain(
      "listScoreboardControlIncidentResolutions",
    );
  });

  it("restores incident-resolution routes", () => {
    expect(route).toContain(
      "/scoreboard-control-incident-resolutions",
    );

    expect(route).toContain(
      "/scoreboard-control-incidents/:auditId",
    );
  });

  it("requires a note for resolved incidents", () => {
    expect(route).toContain(
      "A resolution note is required when resolving an incident.",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.9 incident-resolution recovery installed"
echo "============================================================"
echo
echo "Restored:"
echo "  - scoreboardControlIncidentResolution.ts"
echo "  - incident-resolution GET route"
echo "  - incident update PUT route"
echo "  - actor attribution"
echo "  - resolution-note enforcement"
echo "  - UI hook verification"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry:"
echo "  bash sportsos-milestone-15.10-game-day-control-safety-acceptance-closeout.sh"
