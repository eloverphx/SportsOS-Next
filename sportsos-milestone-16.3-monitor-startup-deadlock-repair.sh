#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-16.3-monitor-startup-deadlock-repair-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

SERVICE="$ROOT/apps/api/src/services/scoreboardReadinessIncidentMonitor.ts"
APP="$ROOT/apps/api/src/app.ts"
TEST="$ROOT/packages/core/test/readiness-monitor-startup-deadlock-repair-16.3.test.ts"

for required in "$SERVICE" "$APP"; do
  [[ -f "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

for file in \
  "apps/api/src/services/scoreboardReadinessIncidentMonitor.ts" \
  "apps/api/src/app.ts" \
  "packages/core/test/readiness-monitor-startup-deadlock-repair-16.3.test.ts"
do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p packages/core/test

node <<'NODE'
const fs = require("fs");

const serviceFile =
  "apps/api/src/services/scoreboardReadinessIncidentMonitor.ts";

let service =
  fs.readFileSync(
    serviceFile,
    "utf8",
  );

/*
 * The original 16.3 monitor called run() synchronously when start() was
 * invoked. buildApp() invokes start before returning the Fastify instance.
 * run() -> app.inject() -> app.ready() can therefore wait on the same
 * construction lifecycle that has not yet completed.
 *
 * Replace the immediate run with a zero-delay unref'd timer. That preserves
 * prompt startup checks in production without blocking buildApp()/app.ready().
 */
if (
  service.includes(
`  run();

  interval =
    setInterval(
      run,
      cadence,
    );`
  )
) {
  service =
    service.replace(
`  run();

  interval =
    setInterval(
      run,
      cadence,
    );`,
`  const initialRun =
    setTimeout(
      run,
      0,
    );

  initialRun.unref?.();

  interval =
    setInterval(
      run,
      cadence,
    );`
    );
}

if (
  !service.includes(
    "const initialRun ="
  )
) {
  throw new Error(
    "Unable to locate or repair immediate readiness-monitor startup.",
  );
}

fs.writeFileSync(
  serviceFile,
  service,
);
NODE

node <<'NODE'
const fs = require("fs");

const appFile =
  "apps/api/src/app.ts";

let text =
  fs.readFileSync(
    appFile,
    "utf8",
  );

const oldBlock =
`  startScoreboardReadinessIncidentMonitor(
    app,
  );

`;

const newBlock =
`  const stopScoreboardReadinessIncidentMonitor =
    startScoreboardReadinessIncidentMonitor(
      app,
    );

  app.addHook(
    "onClose",
    async () => {
      stopScoreboardReadinessIncidentMonitor();
    },
  );

`;

if (text.includes(oldBlock)) {
  text =
    text.replace(
      oldBlock,
      newBlock,
    );
} else if (
  !text.includes(
    "stopScoreboardReadinessIncidentMonitor"
  )
) {
  throw new Error(
    "Unable to locate readiness monitor startup in app.ts.",
  );
}

fs.writeFileSync(
  appFile,
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

describe("Milestone 16.3 readiness monitor startup deadlock repair", () => {
  const monitor = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardReadinessIncidentMonitor.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const app = fs.readFileSync(
    new URL(
      "../../../apps/api/src/app.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("does not run app.inject synchronously during buildApp construction", () => {
    const startup =
      monitor.slice(
        monitor.indexOf(
          "export function startScoreboardReadinessIncidentMonitor",
        ),
      );

    expect(startup).toContain(
      "setTimeout",
    );

    expect(startup).toContain(
      "initialRun.unref",
    );

    expect(startup).not.toContain(
      "\n  run();\n",
    );
  });

  it("retains recurring readiness monitoring", () => {
    expect(monitor).toContain(
      "setInterval",
    );

    expect(monitor).toContain(
      "SPORTSOS_READINESS_MONITOR_INTERVAL_MS",
    );
  });

  it("stops the monitor when Fastify closes", () => {
    expect(app).toContain(
      "stopScoreboardReadinessIncidentMonitor",
    );

    expect(app).toContain(
      '"onClose"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 16.3 startup deadlock repair"
echo "============================================================"
echo
echo "Repair:"
echo "  - removes synchronous readiness check during buildApp()"
echo "  - schedules initial monitor pass asynchronously"
echo "  - keeps recurring 10-second monitoring"
echo "  - clears monitor on Fastify app.close()"
echo "  - prevents platform.test.ts beforeAll/afterAll deadlocks"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
