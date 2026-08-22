#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.6-device-readiness-metrics-reliability-counters-${STAMP}"

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

SERVICE="apps/api/src/services/scoreboardReadinessMetrics.ts"
MONITOR="apps/api/src/services/scoreboardReadinessIncidentMonitor.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/device-readiness-metrics-reliability-counters-16.6.test.ts"

for file in "$SERVICE" "$MONITOR" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type ScoreboardReadinessMetric = {
  deviceId: string;
  readyTransitions: number;
  degradedTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  firstObservedAt: string;
  lastChangedAt: string;
  lastObservedAt: string;
  readyMs: number;
  notReadyMs: number;
};

type Store = {
  version: 1;
  metrics:
    ScoreboardReadinessMetric[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-readiness-metrics.json",
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
        parsed.metrics,
      )
    ) {
      throw new Error(
        "Invalid readiness metrics store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      metrics: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
  );

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function nowIso(): string {
  return new Date().toISOString();
}

export function recordScoreboardReadinessObservation(
  deviceId: string,
  state:
    | "READY"
    | "NOT_READY",
  transitioned: boolean,
): ScoreboardReadinessMetric {
  const now =
    Date.now();

  const nowText =
    new Date(
      now,
    ).toISOString();

  const existing =
    store.metrics.find(
      (item) =>
        item.deviceId ===
        deviceId,
    );

  if (!existing) {
    const created:
      ScoreboardReadinessMetric = {
        deviceId,
        readyTransitions:
          state ===
            "READY"
            ? 1
            : 0,
        degradedTransitions:
          state ===
            "NOT_READY"
            ? 1
            : 0,
        currentState:
          state,
        firstObservedAt:
          nowText,
        lastChangedAt:
          nowText,
        lastObservedAt:
          nowText,
        readyMs:
          0,
        notReadyMs:
          0,
      };

    store.metrics.push(
      created,
    );

    persistStore();

    return created;
  }

  const lastObservedMs =
    Date.parse(
      existing.lastObservedAt,
    );

  const delta =
    Number.isFinite(
      lastObservedMs,
    )
      ? Math.max(
          0,
          now -
            lastObservedMs,
        )
      : 0;

  if (
    existing.currentState ===
      "READY"
  ) {
    existing.readyMs +=
      delta;
  } else {
    existing.notReadyMs +=
      delta;
  }

  existing.lastObservedAt =
    nowText;

  if (
    transitioned &&
    existing.currentState !==
      state
  ) {
    existing.currentState =
      state;

    existing.lastChangedAt =
      nowText;

    if (
      state ===
      "READY"
    ) {
      existing.readyTransitions +=
        1;
    } else {
      existing.degradedTransitions +=
        1;
    }
  }

  persistStore();

  return {
    ...existing,
  };
}

export function listScoreboardReadinessMetrics():
  ScoreboardReadinessMetric[] {
  return [...store.metrics]
    .sort(
      (a, b) =>
        a.deviceId.localeCompare(
          b.deviceId,
        ),
    );
}

export function readinessAvailabilityPercent(
  metric:
    ScoreboardReadinessMetric,
): number {
  const total =
    metric.readyMs +
    metric.notReadyMs;

  if (total <= 0) {
    return metric.currentState ===
      "READY"
      ? 100
      : 0;
  }

  return Math.round(
    (
      metric.readyMs /
      total
    ) *
      10000,
  ) /
    100;
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/services/scoreboardReadinessIncidentMonitor.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { recordScoreboardReadinessObservation } from "./scoreboardReadinessMetrics.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate readiness monitor imports.",
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
    "recordScoreboardReadinessObservation(",
  )
) {
  const firstBaseline =
`      previousState.set(
        key,
        observedState,
      );

      pendingState.delete(
        key,
      );

      continue;`;

  if (!text.includes(firstBaseline)) {
    throw new Error(
      "Unable to locate baseline readiness block.",
    );
  }

  text =
    text.replace(
      firstBaseline,
`      previousState.set(
        key,
        observedState,
      );

      recordScoreboardReadinessObservation(
        assignment.deviceId,
        observedState,
        false,
      );

      pendingState.delete(
        key,
      );

      continue;`
    );

  const sameState =
`    if (
      observedState ===
      committedState
    ) {
      pendingState.delete(
        key,
      );

      continue;
    }`;

  if (!text.includes(sameState)) {
    throw new Error(
      "Unable to locate stable same-state block.",
    );
  }

  text =
    text.replace(
      sameState,
`    if (
      observedState ===
      committedState
    ) {
      recordScoreboardReadinessObservation(
        assignment.deviceId,
        observedState,
        false,
      );

      pendingState.delete(
        key,
      );

      continue;
    }`
    );

  const commitBlock =
`    previousState.set(
      key,
      observedState,
    );

    pendingState.delete(
      key,
    );`;

  if (!text.includes(commitBlock)) {
    throw new Error(
      "Unable to locate committed transition block.",
    );
  }

  text =
    text.replace(
      commitBlock,
`    previousState.set(
      key,
      observedState,
    );

    recordScoreboardReadinessObservation(
      assignment.deviceId,
      observedState,
      true,
    );

    pendingState.delete(
      key,
    );`
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
  "apps/api/src/routes/scoreboardControlPolicy.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { listScoreboardReadinessMetrics, readinessAvailabilityPercent } from "../services/scoreboardReadinessMetrics.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate policy route imports.",
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
    "/scoreboard-control-readiness-metrics",
  )
) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(marker);

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
      "Unable to locate route registration body.",
    );
  }

  const route =
`
  app.get(
    "/scoreboard-control-readiness-metrics",
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

      const metrics =
        listScoreboardReadinessMetrics();

      return {
        success: true,
        data: {
          metrics:
            metrics.map(
              (metric) => ({
                ...metric,
                availabilityPercent:
                  readinessAvailabilityPercent(
                    metric,
                  ),
              }),
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

if (!text.includes("type ReadinessMetric")) {
  const marker =
    "type ReadinessEvent";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate ReadinessEvent type.",
    );
  }

  text =
    text.slice(0, idx) +
`type ReadinessMetric = {
  deviceId: string;
  readyTransitions: number;
  degradedTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  firstObservedAt: string;
  lastChangedAt: string;
  lastObservedAt: string;
  readyMs: number;
  notReadyMs: number;
  availabilityPercent: number;
};

` +
    text.slice(idx);
}

if (!text.includes("readinessMetrics")) {
  const marker =
    "const [readinessEvents, setReadinessEvents]";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate readiness events state.",
    );
  }

  text =
    text.slice(0, idx) +
`const [readinessMetrics, setReadinessMetrics] =
    useState<ReadinessMetric[]>([]);

  ` +
    text.slice(idx);
}

if (
  !text.includes(
    "/scoreboard-control-readiness-metrics",
  )
) {
  const fetchAnchor =
`        fetch(
          \`\${API_BASE}/scoreboard-control-readiness-events?limit=50\`,
          { cache: "no-store" },
        ),`;

  if (!text.includes(fetchAnchor)) {
    throw new Error(
      "Unable to locate readiness events fetch.",
    );
  }

  text =
    text.replace(
      fetchAnchor,
`${fetchAnchor}
        fetch(
          \`\${API_BASE}/scoreboard-control-readiness-metrics\`,
          { cache: "no-store" },
        ),`
    );

  const destructure =
    "        readinessEventsResponse,\n";

  if (!text.includes(destructure)) {
    throw new Error(
      "Unable to locate readiness events response destructure.",
    );
  }

  text =
    text.replace(
      destructure,
      destructure +
        "        readinessMetricsResponse,\n",
    );

  const responseBlock =
`      if (readinessEventsResponse.ok) {
        const readinessEventsJson =
          await readinessEventsResponse.json();

        setReadinessEvents(
          readinessEventsJson?.data?.events ??
          [],
        );
      }`;

  if (!text.includes(responseBlock)) {
    throw new Error(
      "Unable to locate readiness events response block.",
    );
  }

  text =
    text.replace(
      responseBlock,
`${responseBlock}

      if (readinessMetricsResponse.ok) {
        const readinessMetricsJson =
          await readinessMetricsResponse.json();

        setReadinessMetrics(
          readinessMetricsJson?.data?.metrics ??
          [],
        );
      }`
    );
}

if (!text.includes("Device Reliability Metrics")) {
  const marker =
    '      <div className="mt-6 rounded-xl border border-slate-800 p-4">\n        <div className="flex flex-wrap items-center justify-between gap-3">\n          <div>\n            <h3 className="font-semibold">\n              Readiness Recovery Timeline';

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate readiness recovery timeline.",
    );
  }

  const block =
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div>
          <h3 className="font-semibold">
            Device Reliability Metrics
          </h3>
          <p className="mt-1 text-sm text-slate-500">
            Long-lived readiness counters derived from server heartbeat observations.
          </p>
        </div>

        {readinessMetrics.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No readiness metrics recorded yet.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">Device</th>
                  <th className="pb-2 pr-4">State</th>
                  <th className="pb-2 pr-4">Availability</th>
                  <th className="pb-2 pr-4">Degraded</th>
                  <th className="pb-2 pr-4">Recovered</th>
                  <th className="pb-2">Last Change</th>
                </tr>
              </thead>
              <tbody>
                {readinessMetrics.map(
                  (metric) => (
                    <tr
                      key={metric.deviceId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 font-mono text-xs">
                        {metric.deviceId}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.currentState}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.availabilityPercent.toFixed(2)}%
                      </td>
                      <td className="py-3 pr-4">
                        {metric.degradedTransitions}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.readyTransitions}
                      </td>
                      <td className="py-3 text-xs text-slate-400">
                        {metric.lastChangedAt}
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
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

describe("Milestone 16.6 device readiness metrics / reliability counters", () => {
  const metrics = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessMetrics.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
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

  it("persists per-device readiness counters", () => {
    expect(metrics).toContain(
      "scoreboard-readiness-metrics.json",
    );

    expect(metrics).toContain(
      "readyTransitions",
    );

    expect(metrics).toContain(
      "degradedTransitions",
    );
  });

  it("tracks ready and not-ready duration", () => {
    expect(metrics).toContain(
      "readyMs",
    );

    expect(metrics).toContain(
      "notReadyMs",
    );
  });

  it("records readiness observations from the monitor", () => {
    expect(monitor).toContain(
      "recordScoreboardReadinessObservation",
    );
  });

  it("exposes availability metrics through an authorized API", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-metrics",
    );

    expect(route).toContain(
      "availabilityPercent",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("shows device reliability metrics in operator UI", () => {
    expect(panel).toContain(
      "Device Reliability Metrics",
    );

    expect(panel).toContain(
      "Availability",
    );

    expect(panel).toContain(
      "Degraded",
    );

    expect(panel).toContain(
      "Recovered",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent readiness metrics store"
echo "  - per-device degraded/recovered transition counters"
echo "  - current readiness state"
echo "  - ready/not-ready duration counters"
echo "  - availability percentage calculation"
echo "  - GET /scoreboard-control-readiness-metrics"
echo "  - Device Reliability Metrics operator UI"
echo "  - Milestone 16.6 regression tests"
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
echo "  Milestone 16.7 - Reliability Thresholds / At-Risk Device Classification"
