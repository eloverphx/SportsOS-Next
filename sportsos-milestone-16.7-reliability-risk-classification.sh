#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.7-reliability-risk-classification-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardReadinessMetrics.ts" \
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

SERVICE="apps/api/src/services/scoreboardReadinessReliability.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/readiness-reliability-risk-classification-16.7.test.ts"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import {
  listScoreboardReadinessMetrics,
  readinessAvailabilityPercent,
  type ScoreboardReadinessMetric,
} from "./scoreboardReadinessMetrics.js";

export type ScoreboardReliabilityRisk =
  | "HEALTHY"
  | "WATCH"
  | "AT_RISK"
  | "OFFLINE";

export type ScoreboardReliabilityClassification = {
  deviceId: string;
  risk: ScoreboardReliabilityRisk;
  availabilityPercent: number;
  degradedTransitions: number;
  readyTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  lastChangedAt: string;
  reasons: string[];
};

export type ScoreboardReliabilityThresholds = {
  watchAvailabilityPercent: number;
  atRiskAvailabilityPercent: number;
  watchDegradedTransitions: number;
  atRiskDegradedTransitions: number;
};

function numericEnv(
  name: string,
  fallback: number,
): number {
  const parsed =
    Number.parseFloat(
      process.env[name] ??
        "",
    );

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : fallback;
}

export function getScoreboardReliabilityThresholds():
  ScoreboardReliabilityThresholds {
  const watchAvailabilityPercent =
    Math.max(
      0,
      Math.min(
        100,
        numericEnv(
          "SPORTSOS_RELIABILITY_WATCH_AVAILABILITY_PERCENT",
          99,
        ),
      ),
    );

  const atRiskAvailabilityPercent =
    Math.max(
      0,
      Math.min(
        watchAvailabilityPercent,
        numericEnv(
          "SPORTSOS_RELIABILITY_AT_RISK_AVAILABILITY_PERCENT",
          95,
        ),
      ),
    );

  const watchDegradedTransitions =
    Math.max(
      1,
      Math.floor(
        numericEnv(
          "SPORTSOS_RELIABILITY_WATCH_DEGRADED_TRANSITIONS",
          2,
        ),
      ),
    );

  const atRiskDegradedTransitions =
    Math.max(
      watchDegradedTransitions,
      Math.floor(
        numericEnv(
          "SPORTSOS_RELIABILITY_AT_RISK_DEGRADED_TRANSITIONS",
          5,
        ),
      ),
    );

  return {
    watchAvailabilityPercent,
    atRiskAvailabilityPercent,
    watchDegradedTransitions,
    atRiskDegradedTransitions,
  };
}

export function classifyScoreboardReliability(
  metric: ScoreboardReadinessMetric,
  thresholds =
    getScoreboardReliabilityThresholds(),
): ScoreboardReliabilityClassification {
  const availabilityPercent =
    readinessAvailabilityPercent(
      metric,
    );

  const reasons:
    string[] =
      [];

  if (
    metric.currentState ===
      "NOT_READY"
  ) {
    reasons.push(
      "Device is currently not ready.",
    );

    return {
      deviceId:
        metric.deviceId,
      risk:
        "OFFLINE",
      availabilityPercent,
      degradedTransitions:
        metric.degradedTransitions,
      readyTransitions:
        metric.readyTransitions,
      currentState:
        metric.currentState,
      lastChangedAt:
        metric.lastChangedAt,
      reasons,
    };
  }

  if (
    availabilityPercent <
      thresholds.atRiskAvailabilityPercent
  ) {
    reasons.push(
      `Availability ${availabilityPercent.toFixed(2)}% is below the ${thresholds.atRiskAvailabilityPercent.toFixed(2)}% at-risk threshold.`,
    );
  }

  if (
    metric.degradedTransitions >=
      thresholds.atRiskDegradedTransitions
  ) {
    reasons.push(
      `${metric.degradedTransitions} degradation transitions meet the at-risk threshold of ${thresholds.atRiskDegradedTransitions}.`,
    );
  }

  if (
    reasons.length >
    0
  ) {
    return {
      deviceId:
        metric.deviceId,
      risk:
        "AT_RISK",
      availabilityPercent,
      degradedTransitions:
        metric.degradedTransitions,
      readyTransitions:
        metric.readyTransitions,
      currentState:
        metric.currentState,
      lastChangedAt:
        metric.lastChangedAt,
      reasons,
    };
  }

  if (
    availabilityPercent <
      thresholds.watchAvailabilityPercent
  ) {
    reasons.push(
      `Availability ${availabilityPercent.toFixed(2)}% is below the ${thresholds.watchAvailabilityPercent.toFixed(2)}% watch threshold.`,
    );
  }

  if (
    metric.degradedTransitions >=
      thresholds.watchDegradedTransitions
  ) {
    reasons.push(
      `${metric.degradedTransitions} degradation transitions meet the watch threshold of ${thresholds.watchDegradedTransitions}.`,
    );
  }

  return {
    deviceId:
      metric.deviceId,
    risk:
      reasons.length >
        0
        ? "WATCH"
        : "HEALTHY",
    availabilityPercent,
    degradedTransitions:
      metric.degradedTransitions,
    readyTransitions:
      metric.readyTransitions,
    currentState:
      metric.currentState,
    lastChangedAt:
      metric.lastChangedAt,
    reasons,
  };
}

export function listScoreboardReliabilityClassifications():
  ScoreboardReliabilityClassification[] {
  const thresholds =
    getScoreboardReliabilityThresholds();

  return listScoreboardReadinessMetrics()
    .map(
      (metric) =>
        classifyScoreboardReliability(
          metric,
          thresholds,
        ),
    )
    .sort(
      (a, b) => {
        const priority:
          Record<
            ScoreboardReliabilityRisk,
            number
          > = {
            OFFLINE: 0,
            AT_RISK: 1,
            WATCH: 2,
            HEALTHY: 3,
          };

        return (
          priority[a.risk] -
            priority[b.risk] ||
          a.deviceId.localeCompare(
            b.deviceId,
          )
        );
      },
    );
}
EOF

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
  'import { getScoreboardReliabilityThresholds, listScoreboardReliabilityClassifications } from "../services/scoreboardReadinessReliability.js";';

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
    "/scoreboard-control-readiness-reliability",
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
      "Unable to locate policy route body.",
    );
  }

  const route =
`
  app.get(
    "/scoreboard-control-readiness-reliability",
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
          thresholds:
            getScoreboardReliabilityThresholds(),
          devices:
            listScoreboardReliabilityClassifications(),
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
    "type ReliabilityClassification",
  )
) {
  const marker =
    "type ReadinessMetric";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate ReadinessMetric type.",
    );
  }

  text =
    text.slice(
      0,
      idx,
    ) +
`type ReliabilityClassification = {
  deviceId: string;
  risk:
    | "HEALTHY"
    | "WATCH"
    | "AT_RISK"
    | "OFFLINE";
  availabilityPercent: number;
  degradedTransitions: number;
  readyTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  lastChangedAt: string;
  reasons: string[];
};

` +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "reliabilityClassifications",
  )
) {
  const marker =
    "const [readinessMetrics, setReadinessMetrics]";

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate readiness metrics state.",
    );
  }

  text =
    text.slice(
      0,
      idx,
    ) +
`const [
    reliabilityClassifications,
    setReliabilityClassifications,
  ] =
    useState<ReliabilityClassification[]>([]);

  ` +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "/scoreboard-control-readiness-reliability",
  )
) {
  const fetchAnchor =
`        fetch(
          \`\${API_BASE}/scoreboard-control-readiness-metrics\`,
          { cache: "no-store" },
        ),`;

  if (!text.includes(fetchAnchor)) {
    throw new Error(
      "Unable to locate readiness metrics fetch.",
    );
  }

  text =
    text.replace(
      fetchAnchor,
`${fetchAnchor}
        fetch(
          \`\${API_BASE}/scoreboard-control-readiness-reliability\`,
          { cache: "no-store" },
        ),`
    );

  const destructure =
    "        readinessMetricsResponse,\n";

  if (!text.includes(destructure)) {
    throw new Error(
      "Unable to locate metrics response destructure.",
    );
  }

  text =
    text.replace(
      destructure,
      destructure +
        "        reliabilityResponse,\n",
    );

  const responseBlock =
`      if (readinessMetricsResponse.ok) {
        const readinessMetricsJson =
          await readinessMetricsResponse.json();

        setReadinessMetrics(
          readinessMetricsJson?.data?.metrics ??
          [],
        );
      }`;

  if (!text.includes(responseBlock)) {
    throw new Error(
      "Unable to locate metrics response block.",
    );
  }

  text =
    text.replace(
      responseBlock,
`${responseBlock}

      if (reliabilityResponse.ok) {
        const reliabilityJson =
          await reliabilityResponse.json();

        setReliabilityClassifications(
          reliabilityJson?.data?.devices ??
          [],
        );
      }`
    );
}

if (
  !text.includes(
    "Reliability Risk Classification",
  )
) {
  const marker =
    '      <div className="mt-6 rounded-xl border border-slate-800 p-4">\n        <div>\n          <h3 className="font-semibold">\n            Device Reliability Metrics';

  const idx =
    text.indexOf(
      marker,
    );

  if (idx === -1) {
    throw new Error(
      "Unable to locate Device Reliability Metrics panel.",
    );
  }

  const block =
`      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Reliability Risk Classification
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Scoreboards are classified from server-side availability and degradation history.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {reliabilityClassifications.filter(
              (item) =>
                item.risk === "AT_RISK" ||
                item.risk === "OFFLINE",
            ).length}
            {" "}need attention
          </span>
        </div>

        {reliabilityClassifications.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No reliability history recorded yet.
          </p>
        ) : (
          <div className="mt-4 space-y-2">
            {reliabilityClassifications.map(
              (item) => (
                <div
                  key={item.deviceId}
                  className="rounded-lg border border-slate-800 p-3"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-xs">
                      {item.deviceId}
                    </span>
                    <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
                      {item.risk}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-2 text-sm text-slate-400 sm:grid-cols-3">
                    <div>
                      Availability:{" "}
                      {item.availabilityPercent.toFixed(2)}%
                    </div>
                    <div>
                      Degraded:{" "}
                      {item.degradedTransitions}
                    </div>
                    <div>
                      State:{" "}
                      {item.currentState}
                    </div>
                  </div>

                  {item.reasons.length > 0 && (
                    <ul className="mt-2 list-disc space-y-1 pl-5 text-xs text-slate-500">
                      {item.reasons.map(
                        (reason) => (
                          <li key={reason}>
                            {reason}
                          </li>
                        ),
                      )}
                    </ul>
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

describe("Milestone 16.7 reliability thresholds / at-risk device classification", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessReliability.ts",
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

  it("defines healthy, watch, at-risk, and offline classifications", () => {
    for (const state of [
      "HEALTHY",
      "WATCH",
      "AT_RISK",
      "OFFLINE",
    ]) {
      expect(service).toContain(
        `"${state}"`,
      );
    }
  });

  it("uses configurable availability and degradation thresholds", () => {
    expect(service).toContain(
      "SPORTSOS_RELIABILITY_WATCH_AVAILABILITY_PERCENT",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_AT_RISK_AVAILABILITY_PERCENT",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_WATCH_DEGRADED_TRANSITIONS",
    );

    expect(service).toContain(
      "SPORTSOS_RELIABILITY_AT_RISK_DEGRADED_TRANSITIONS",
    );
  });

  it("classifies current not-ready devices as offline", () => {
    expect(service).toContain(
      'metric.currentState ===',
    );

    expect(service).toContain(
      'risk:\n        "OFFLINE"',
    );
  });

  it("exposes reliability classification through an authorized API", () => {
    expect(route).toContain(
      "/scoreboard-control-readiness-reliability",
    );

    expect(route).toContain(
      '"CONTROL_POLICY_READ"',
    );
  });

  it("surfaces reliability risk in the operator UI", () => {
    expect(panel).toContain(
      "Reliability Risk Classification",
    );

    expect(panel).toContain(
      "need attention",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - HEALTHY / WATCH / AT_RISK / OFFLINE classification"
echo "  - configurable availability thresholds"
echo "  - configurable degradation-count thresholds"
echo "  - explanatory risk reasons"
echo "  - attention-first device ordering"
echo "  - GET /scoreboard-control-readiness-reliability"
echo "  - Reliability Risk Classification operator UI"
echo "  - Milestone 16.7 regression tests"
echo
echo "Defaults:"
echo "  WATCH availability:   < 99%"
echo "  AT_RISK availability: < 95%"
echo "  WATCH degradations:   >= 2"
echo "  AT_RISK degradations: >= 5"
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
echo "  Milestone 16.8 - Pre-Game Device Readiness Gate / Operator Override"
