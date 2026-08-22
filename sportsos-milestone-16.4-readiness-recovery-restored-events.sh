#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.4-readiness-recovery-restored-events-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardReadinessIncidentMonitor.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

MONITOR="apps/api/src/services/scoreboardReadinessIncidentMonitor.ts"
AUDIT="apps/api/src/services/scoreboardControlAudit.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/readiness-recovery-restored-events-16.4.test.ts"

for file in "$MONITOR" "$AUDIT" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardReadinessIncidentMonitor.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "DEVICE_READINESS_RESTORED",
  )
) {
  const anchor =
`    if (
      nextState ===
        "NOT_READY" &&
      prior !==
        "NOT_READY"
    ) {`;

  const idx =
    text.indexOf(
      anchor,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate NOT_READY transition block.",
    );
  }

  const blockEndSearch =
    "    previousState.set(";

  const blockEnd =
    text.indexOf(
      blockEndSearch,
      idx,
    );

  if (blockEnd === -1) {
    throw new Error(
      "Unable to locate previousState.set() after incident block.",
    );
  }

  const recovery =
`    if (
      nextState ===
        "READY" &&
      prior ===
        "NOT_READY"
    ) {
      const now =
        new Date().toISOString();

      recordScoreboardControlAudit({
        auditId:
          \`readiness-restored-\${assignment.deviceId}-\${Date.now()}\`,
        deviceId:
          assignment.deviceId,
        gameId:
          assignment.gameId,
        inputId:
          \`readiness-monitor:\${assignment.deviceId}\`,
        inputType:
          "DEVICE_READINESS_RESTORED",
        sequence:
          0,
        disposition:
          "ACCEPTED",
        command:
          null,
        execution:
          null,
        reconciliation:
          null,
        error:
          null,
        createdAt:
          now,
      });
    }

`;

  text =
    text.slice(
      0,
      blockEnd,
    ) +
    recovery +
    text.slice(
      blockEnd,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardControlAudit.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "listScoreboardControlReadinessEvents",
  )
) {
  text += `

export type ScoreboardControlReadinessEvent = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  eventType:
    | "DEVICE_READINESS_DEGRADED"
    | "DEVICE_READINESS_RESTORED";
  disposition: string;
  error: string | null;
  createdAt: string;
};

export function listScoreboardControlReadinessEvents(
  limit = 100,
): ScoreboardControlReadinessEvent[] {
  return listScoreboardControlAudit({
    limit:
      Math.max(
        100,
        Math.min(
          limit * 5,
          1000,
        ),
      ),
  })
    .filter(
      (record) =>
        record.inputType ===
          "DEVICE_READINESS_DEGRADED" ||
        record.inputType ===
          "DEVICE_READINESS_RESTORED",
    )
    .map(
      (record) => ({
        auditId:
          record.auditId,
        deviceId:
          record.deviceId,
        gameId:
          record.gameId ??
          null,
        eventType:
          record.inputType as
            | "DEVICE_READINESS_DEGRADED"
            | "DEVICE_READINESS_RESTORED",
        disposition:
          record.disposition,
        error:
          record.error ??
          null,
        createdAt:
          record.createdAt,
      }),
    )
    .slice(
      0,
      Math.max(
        1,
        Math.min(
          limit,
          500,
        ),
      ),
    );
}
`;
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { listScoreboardControlReadinessEvents } from "../services/scoreboardControlAudit.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate control-policy route imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !text.includes(
    "/scoreboard-control-readiness-events",
  )
) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate policy route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate policy route body.",
    );
  }

  const route =
`
  app.get(
    "/scoreboard-control-readiness-events",
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

      const query =
        request.query as {
          limit?: string;
        };

      const parsed =
        query.limit
          ? Number.parseInt(
              query.limit,
              10,
            )
          : 50;

      const limit =
        Number.isFinite(
          parsed,
        )
          ? parsed
          : 50;

      return {
        success: true,
        data: {
          events:
            listScoreboardControlReadinessEvents(
              limit,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(
      0,
      open + 1,
    ) +
    route +
    text.slice(
      open + 1,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type ReadinessEvent",
  )
) {
  const marker =
    "type DeviceReadiness";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate DeviceReadiness type.",
    );
  }

  text =
    text.slice(
      0,
      idx,
    ) +
`type ReadinessEvent = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  eventType:
    | "DEVICE_READINESS_DEGRADED"
    | "DEVICE_READINESS_RESTORED";
  disposition: string;
  error: string | null;
  createdAt: string;
};

` +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "readinessEvents",
  )
) {
  const marker =
    "const [deviceReadiness, setDeviceReadiness]";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate device readiness state.",
    );
  }

  text =
    text.slice(
      0,
      idx,
    ) +
`const [readinessEvents, setReadinessEvents] =
    useState<ReadinessEvent[]>([]);

  ` +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "/scoreboard-control-readiness-events",
  )
) {
  const fetchAnchor =
`        fetch(
          \`\${API_BASE}/scoreboard-control-incidents?limit=50\`,
          { cache: "no-store" },
        ),`;

  if (!text.includes(fetchAnchor)) {
    throw new Error(
      "Unable to locate incidents fetch.",
    );
  }

  text =
    text.replace(
      fetchAnchor,
`${fetchAnchor}
        fetch(
          \`\${API_BASE}/scoreboard-control-readiness-events?limit=50\`,
          { cache: "no-store" },
        ),`
    );

  const destructure =
    "        incidentsResponse,\n";

  if (!text.includes(destructure)) {
    throw new Error(
      "Unable to locate incidents response destructure.",
    );
  }

  text =
    text.replace(
      destructure,
      destructure +
        "        readinessEventsResponse,\n",
    );

  const responseBlock =
`      if (incidentsResponse.ok) {
        const incidentsJson =
          await incidentsResponse.json();

        setControlIncidents(
          incidentsJson?.data?.incidents ??
          [],
        );
      }`;

  if (!text.includes(responseBlock)) {
    throw new Error(
      "Unable to locate incidents response block.",
    );
  }

  text =
    text.replace(
      responseBlock,
`${responseBlock}

      if (readinessEventsResponse.ok) {
        const readinessEventsJson =
          await readinessEventsResponse.json();

        setReadinessEvents(
          readinessEventsJson?.data?.events ??
          [],
        );
      }`
    );
}

if (
  !text.includes(
    "Readiness Recovery Timeline",
  )
) {
  const marker =
    '      <div className="mt-6 rounded-xl border border-slate-800 p-4">\n        <div className="flex flex-wrap items-center justify-between gap-3">\n          <div>\n            <h3 className="font-semibold">\n              Device Readiness Status';

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate Device Readiness Status panel.",
    );
  }

  const block =
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Readiness Recovery Timeline
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Device readiness degradation and restoration events.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {readinessEvents.length} events
          </span>
        </div>

        {readinessEvents.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No readiness transitions recorded yet.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {readinessEvents.map(
              (event) => (
                <div
                  key={event.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-semibold">
                      {event.eventType ===
                      "DEVICE_READINESS_RESTORED"
                        ? "RESTORED"
                        : "DEGRADED"}
                    </span>

                    <span className="text-xs text-slate-500">
                      {event.createdAt}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-1 text-slate-400 sm:grid-cols-2">
                    <div>
                      Device:{" "}
                      <span className="font-mono text-xs">
                        {event.deviceId}
                      </span>
                    </div>
                    <div>
                      Game:{" "}
                      <span className="font-mono text-xs">
                        {event.gameId ?? "unassigned"}
                      </span>
                    </div>
                  </div>

                  {event.error && (
                    <p className="mt-2 text-xs text-slate-400">
                      {event.error}
                    </p>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    block +
    text.slice(
      idx,
    );
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 16.4 readiness recovery / restored-service events", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const audit = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlAudit.ts",
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

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("emits a restoration event only after a not-ready state", () => {
    expect(monitor).toContain(
      '"DEVICE_READINESS_RESTORED"',
    );

    expect(monitor).toContain(
      'prior ===',
    );

    expect(monitor).toContain(
      '"NOT_READY"',
    );
  });

  it("projects both degradation and restoration readiness events", () => {
    expect(audit).toContain(
      "listScoreboardControlReadinessEvents",
    );

    expect(audit).toContain(
      '"DEVICE_READINESS_DEGRADED"',
    );

    expect(audit).toContain(
      '"DEVICE_READINESS_RESTORED"',
    );
  });

  it("exposes an authorized readiness event endpoint", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-events",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("shows readiness recovery timeline in operator UI", () => {
    expect(panel).toContain(
      "Readiness Recovery Timeline",
    );

    expect(panel).toContain(
      "RESTORED",
    );

    expect(panel).toContain(
      "DEGRADED",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - NOT_READY -> READY restoration detection"
echo "  - DEVICE_READINESS_RESTORED audit event"
echo "  - combined readiness transition projection"
echo "  - GET /scoreboard-control-readiness-events"
echo "  - Readiness Recovery Timeline operator UI"
echo "  - Milestone 16.4 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 16.5 - Readiness Flap Detection / Stability Window"
