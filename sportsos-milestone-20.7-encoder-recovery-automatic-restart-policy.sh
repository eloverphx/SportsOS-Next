#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.7-encoder-recovery-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

RUNTIME="apps/api/src/services/encoderRuntime.ts"
SESSION="apps/api/src/services/encoderSession.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/encoder-recovery-policy-20.7.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "$RUNTIME" \
  "$SESSION" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$RUNTIME" "$SESSION" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/services/encoderRuntime.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("export type EncoderRecoveryState")) {
  const marker = "export type EncoderTelemetryHealth";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate telemetry types.");

  const type =
`export type EncoderRecoveryState =
  | "IDLE"
  | "SCHEDULED"
  | "RESTARTING"
  | "EXHAUSTED";

export type EncoderRecoverySnapshot = {
  gameId: string;
  state: EncoderRecoveryState;
  attempt: number;
  maxAttempts: number;
  nextRetryAt: string | null;
  lastFailureAt: string | null;
};

`;

  text = text.slice(0, idx) + type + text.slice(idx);
}

if (!text.includes("const recovery =")) {
  const marker = "const telemetry =";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate telemetry map.");

  const block =
`const recovery =
  new Map<
    string,
    EncoderRecoverySnapshot
  >();

function maxRecoveryAttempts(): number {
  const parsed =
    Number.parseInt(
      process.env.SPORTSOS_ENCODER_MAX_RESTARTS ??
        "3",
      10,
    );

  return Number.isFinite(parsed) && parsed >= 0
    ? parsed
    : 3;
}

function recoveryBackoffMs(
  attempt: number,
): number {
  const base =
    Number.parseInt(
      process.env.SPORTSOS_ENCODER_RESTART_BACKOFF_MS ??
        "3000",
      10,
    );

  const safeBase =
    Number.isFinite(base) && base >= 500
      ? base
      : 3000;

  return Math.min(
    safeBase *
      Math.max(1, attempt),
    30000,
  );
}

export function getEncoderRecoverySnapshot(
  gameId: string,
): EncoderRecoverySnapshot {
  return recovery.get(gameId) ?? {
    gameId,
    state: "IDLE",
    attempt: 0,
    maxAttempts: maxRecoveryAttempts(),
    nextRetryAt: null,
    lastFailureAt: null,
  };
}

function resetEncoderRecovery(
  gameId: string,
): void {
  recovery.set(
    gameId,
    {
      gameId,
      state: "IDLE",
      attempt: 0,
      maxAttempts: maxRecoveryAttempts(),
      nextRetryAt: null,
      lastFailureAt: null,
    },
  );
}

`;

  text = text.slice(0, idx) + block + text.slice(idx);
}

if (!text.includes("scheduleEncoderRestart")) {
  const marker = "export async function startEncoderRuntime";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate runtime start.");

  const helper =
`async function scheduleEncoderRestart(input: {
  gameId: string;
  destination: StreamDestinationProfile;
}): Promise<void> {
  const current =
    getEncoderRecoverySnapshot(
      input.gameId,
    );

  const nextAttempt =
    current.attempt + 1;

  if (
    nextAttempt >
    current.maxAttempts
  ) {
    recovery.set(
      input.gameId,
      {
        ...current,
        state: "EXHAUSTED",
        nextRetryAt: null,
        lastFailureAt:
          new Date().toISOString(),
      },
    );

    return;
  }

  const delayMs =
    recoveryBackoffMs(
      nextAttempt,
    );

  const nextRetryAt =
    new Date(
      Date.now() +
        delayMs,
    ).toISOString();

  recovery.set(
    input.gameId,
    {
      gameId:
        input.gameId,
      state:
        "SCHEDULED",
      attempt:
        nextAttempt,
      maxAttempts:
        current.maxAttempts,
      nextRetryAt,
      lastFailureAt:
        new Date().toISOString(),
    },
  );

  setTimeout(
    () => {
      const snapshot =
        getEncoderRecoverySnapshot(
          input.gameId,
        );

      if (
        snapshot.state !==
          "SCHEDULED" ||
        snapshot.attempt !==
          nextAttempt
      ) {
        return;
      }

      recovery.set(
        input.gameId,
        {
          ...snapshot,
          state:
            "RESTARTING",
          nextRetryAt:
            null,
        },
      );

      void startEncoderRuntime({
        gameId:
          input.gameId,
        destination:
          input.destination,
        recoveryAttempt:
          true,
      }).catch(
        () => {
          void scheduleEncoderRestart(
            input,
          );
        },
      );
    },
    delayMs,
  );
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

text = text.replace(
`export async function startEncoderRuntime(input: {
  gameId: string;
  destination:
    StreamDestinationProfile;
}): Promise<void> {`,
`export async function startEncoderRuntime(input: {
  gameId: string;
  destination:
    StreamDestinationProfile;
  recoveryAttempt?: boolean;
}): Promise<void> {`
);

if (!text.includes("if (!input.recoveryAttempt)")) {
  const marker = `  if (
    runtimes.has(
      input.gameId,
    )
  ) {
    return;
  }`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate runtime duplicate guard.");
  }

  text = text.replace(
    marker,
`${marker}

  if (!input.recoveryAttempt) {
    resetEncoderRecovery(
      input.gameId,
    );
  }`
  );
}

if (!text.includes("scheduleEncoderRestart({")) {
  const marker = `      markEncoderError(
        input.gameId,
        \`FFmpeg exited unexpectedly`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error("Unable to locate unexpected exit handler.");
  }

  const blockEnd = text.indexOf("      );", idx);
  if (blockEnd === -1) {
    throw new Error("Unable to locate markEncoderError end.");
  }

  const insertAt = blockEnd + "      );".length;

  const addition =
`

      void scheduleEncoderRestart({
        gameId:
          input.gameId,
        destination:
          input.destination,
      });`;

  text =
    text.slice(0, insertAt) +
    addition +
    text.slice(insertAt);
}

if (!text.includes("resetEncoderRecovery(") || !text.includes("markEncoderLive(")) {
  throw new Error("Recovery wiring incomplete.");
}

if (!text.includes("recovery:")) {
  text = text.replace(
`  telemetry:
    EncoderTelemetry;
} {`,
`  telemetry:
    EncoderTelemetry;
  recovery:
    EncoderRecoverySnapshot;
} {`
  );

  text = text.replace(
`    telemetry:
      getEncoderTelemetry(
        gameId,
      ),
  };
}`,
`    telemetry:
      getEncoderTelemetry(
        gameId,
      ),
    recovery:
      getEncoderRecoverySnapshot(
        gameId,
      ),
  };
}`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/encoderSessions.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("recovery:")) {
  text = text.replace(
`          telemetry:
            snapshot.telemetry,
        },`,
`          telemetry:
            snapshot.telemetry,
          recovery:
            snapshot.recovery,
        },`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type EncoderRecoverySnapshot =")) {
  const marker = "type StreamDestinationProfile = {";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate stream profile type.");

  const type =
`type EncoderRecoverySnapshot = {
  gameId: string;
  state:
    | "IDLE"
    | "SCHEDULED"
    | "RESTARTING"
    | "EXHAUSTED";
  attempt: number;
  maxAttempts: number;
  nextRetryAt: string | null;
  lastFailureAt: string | null;
};

`;

  text = text.slice(0, idx) + type + text.slice(idx);
}

if (!text.includes("const [encoderRecovery")) {
  const marker =
`  const [
    encoderTelemetry,
    setEncoderTelemetry,
  ] =
    useState<EncoderTelemetry | null>(
      null,
    );`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate telemetry state.");
  }

  text = text.replace(
    marker,
`${marker}

  const [
    encoderRecovery,
    setEncoderRecovery,
  ] =
    useState<EncoderRecoverySnapshot | null>(
      null,
    );`
  );
}

if (!text.includes("setEncoderRecovery(")) {
  const marker =
`          setEncoderTelemetry(json?.data?.telemetry ?? null);`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate telemetry polling result.");
  }

  text = text.replace(
    marker,
`${marker}
          setEncoderRecovery(json?.data?.recovery ?? null);`
  );
}

if (!text.includes("Recovery State")) {
  const marker =
`        {encoderTelemetry?.lastProgressAt && (
          <p className="mt-3 text-xs text-slate-500">
            Last encoder progress: {encoderTelemetry.lastProgressAt}
          </p>
        )}`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate telemetry footer.");
  }

  const block =
`${marker}

        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Recovery State
            </div>
            <div className="mt-1 font-semibold">
              {encoderRecovery?.state ?? "IDLE"}
            </div>
          </div>

          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Restart Attempts
            </div>
            <div className="mt-1 font-semibold">
              {encoderRecovery
                ? \`\${encoderRecovery.attempt}/\${encoderRecovery.maxAttempts}\`
                : "0/0"}
            </div>
          </div>

          <div className="rounded border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Next Retry
            </div>
            <div className="mt-1 text-sm">
              {encoderRecovery?.nextRetryAt ?? "--"}
            </div>
          </div>
        </div>`;

  text = text.replace(marker, block);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.7 — Encoder recovery and automatic restart policy

Unexpected FFmpeg exits now trigger bounded automatic recovery.

Defaults:

```text
max restart attempts: 3
base restart backoff: 3000 ms
maximum backoff: 30000 ms
```

Environment overrides:

```text
SPORTSOS_ENCODER_MAX_RESTARTS
SPORTSOS_ENCODER_RESTART_BACKOFF_MS
```

Recovery states:

```text
IDLE
SCHEDULED
RESTARTING
EXHAUSTED
```

Restart attempts are bounded. Once the configured maximum is exceeded, SportsOS enters `EXHAUSTED` and stops retrying automatically.

Operator-requested stop does not trigger automatic recovery.

The operator UI shows recovery state, attempt count, and next retry timestamp.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.7 encoder recovery / automatic restart policy", () => {
  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("uses bounded restart attempts", () => {
    expect(runtime).toContain(
      "SPORTSOS_ENCODER_MAX_RESTARTS",
    );

    expect(runtime).toContain(
      '"EXHAUSTED"',
    );
  });

  it("uses restart backoff", () => {
    expect(runtime).toContain(
      "SPORTSOS_ENCODER_RESTART_BACKOFF_MS",
    );

    expect(runtime).toContain(
      "30000",
    );
  });

  it("schedules restart after unexpected exit", () => {
    expect(runtime).toContain(
      "scheduleEncoderRestart",
    );

    expect(runtime).toContain(
      '"SCHEDULED"',
    );

    expect(runtime).toContain(
      '"RESTARTING"',
    );
  });

  it("does not restart after operator-requested stop", () => {
    expect(runtime).toContain(
      "entry.stopRequested",
    );
  });

  it("shows recovery status in operator UI", () => {
    expect(panel).toContain(
      "Recovery State",
    );

    expect(panel).toContain(
      "Restart Attempts",
    );

    expect(panel).toContain(
      "Next Retry",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.7 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - bounded automatic encoder restart policy"
echo "  - configurable max restart attempts"
echo "  - configurable restart backoff"
echo "  - IDLE/SCHEDULED/RESTARTING/EXHAUSTED recovery states"
echo "  - operator-visible attempt count and next retry"
echo "  - no restart after intentional operator stop"
echo "  - Milestone 20.7 regression tests"
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
echo "  Milestone 20.8 - Encoder Runtime Audit / Failure History"
