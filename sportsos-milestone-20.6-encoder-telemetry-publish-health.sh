#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.6-encoder-telemetry-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

RUNTIME="apps/api/src/services/encoderRuntime.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/encoder-telemetry-publish-health-20.6.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "$RUNTIME" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$RUNTIME" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
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

if (!text.includes("export type EncoderTelemetryHealth")) {
  const marker = "type RuntimeEntry = {";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate RuntimeEntry.");

  const types = `export type EncoderTelemetryHealth =
  | "IDLE"
  | "STARTING"
  | "HEALTHY"
  | "STALE"
  | "ERROR";

export type EncoderTelemetry = {
  gameId: string;
  health: EncoderTelemetryHealth;
  frame: number | null;
  fps: number | null;
  bitrateKbps: number | null;
  totalSizeBytes: number | null;
  outTimeMs: number | null;
  speed: number | null;
  lastProgressAt: string | null;
  startedAt: string | null;
  lastError: string | null;
};

`;

  text = text.slice(0, idx) + types + text.slice(idx);
}

if (!text.includes("const telemetry =")) {
  const marker = "const runtimes =";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate runtimes map.");

  const end = text.indexOf(">();", idx);
  if (end === -1) throw new Error("Unable to locate runtimes map end.");

  const insertAt = end + 4;

  const block = `

const telemetry =
  new Map<
    string,
    EncoderTelemetry
  >();

function baseTelemetry(
  gameId: string,
): EncoderTelemetry {
  return {
    gameId,
    health: "IDLE",
    frame: null,
    fps: null,
    bitrateKbps: null,
    totalSizeBytes: null,
    outTimeMs: null,
    speed: null,
    lastProgressAt: null,
    startedAt: null,
    lastError: null,
  };
}

export function getEncoderTelemetry(
  gameId: string,
): EncoderTelemetry {
  const current =
    telemetry.get(
      gameId,
    ) ??
    baseTelemetry(
      gameId,
    );

  if (
    current.health === "HEALTHY" &&
    current.lastProgressAt &&
    Date.now() -
      Date.parse(
        current.lastProgressAt,
      ) >
      10000
  ) {
    return {
      ...current,
      health: "STALE",
    };
  }

  return {
    ...current,
  };
}
`;

  text = text.slice(0, insertAt) + block + text.slice(insertAt);
}

if (!text.includes('"-progress"')) {
  const marker = `    "-loglevel",
    "warning",`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate FFmpeg loglevel args.");
  }

  text = text.replace(
    marker,
`    "-loglevel",
    "warning",
    "-progress",
    "pipe:1",
    "-nostats",`
  );
}

if (!text.includes("parseProgressLine")) {
  const marker = "function sanitizedMessage(";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate sanitizedMessage.");

  const helpers = `function parseNumeric(
  value: string,
): number | null {
  const parsed =
    Number(
      value,
    );

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : null;
}

function parseProgressLine(
  gameId: string,
  line: string,
): void {
  const separator =
    line.indexOf("=");

  if (separator <= 0) {
    return;
  }

  const key =
    line.slice(
      0,
      separator,
    );

  const value =
    line.slice(
      separator + 1,
    );

  const current =
    telemetry.get(
      gameId,
    ) ??
    baseTelemetry(
      gameId,
    );

  const next: EncoderTelemetry = {
    ...current,
    gameId,
    health: "HEALTHY",
    lastProgressAt:
      new Date().toISOString(),
  };

  if (key === "frame") {
    next.frame =
      parseNumeric(
        value,
      );
  } else if (key === "fps") {
    next.fps =
      parseNumeric(
        value,
      );
  } else if (key === "bitrate") {
    next.bitrateKbps =
      parseNumeric(
        value.replace(
          /kbits\\/s$/i,
          "",
        ),
      );
  } else if (key === "total_size") {
    next.totalSizeBytes =
      parseNumeric(
        value,
      );
  } else if (key === "out_time_ms") {
    const micros =
      parseNumeric(
        value,
      );

    next.outTimeMs =
      micros == null
        ? null
        : Math.floor(
            micros /
            1000,
          );
  } else if (key === "speed") {
    next.speed =
      parseNumeric(
        value.replace(
          /x$/i,
          "",
        ),
      );
  }

  telemetry.set(
    gameId,
    next,
  );
}

`;

  text = text.slice(0, idx) + helpers + text.slice(idx);
}

if (!text.includes("child.stdout.on(")) {
  const marker = `  let stderrTail =
    "";`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate stderr tail block.");
  }

  const stdoutBlock = `  let progressBuffer =
    "";

  child.stdout.on(
    "data",
    (
      chunk:
        Buffer,
    ) => {
      progressBuffer +=
        chunk.toString(
          "utf8",
        );

      const lines =
        progressBuffer.split(
          /\\r?\\n/,
        );

      progressBuffer =
        lines.pop() ??
        "";

      for (const line of lines) {
        parseProgressLine(
          input.gameId,
          line,
        );
      }
    },
  );

`;

  text = text.replace(marker, stdoutBlock + marker);
}

if (!text.includes('health: "STARTING"')) {
  const marker = `  runtimes.set(
    input.gameId,
    entry,
  );`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate runtime registration.");
  }

  text = text.replace(
    marker,
`${marker}

  telemetry.set(
    input.gameId,
    {
      ...baseTelemetry(
        input.gameId,
      ),
      health: "STARTING",
      startedAt:
        new Date().toISOString(),
    },
  );`
  );
}

if (!text.includes("telemetry:")) {
  text = text.replace(
`export function encoderRuntimeSnapshot(
  gameId: string,
): {
  runtimeActive: boolean;
  session:
    ReturnType<
      typeof getEncoderSession
    >;
} {`,
`export function encoderRuntimeSnapshot(
  gameId: string,
): {
  runtimeActive: boolean;
  session:
    ReturnType<
      typeof getEncoderSession
    >;
  telemetry:
    EncoderTelemetry;
} {`
  );

  text = text.replace(
`    session:
      getEncoderSession(
        gameId,
      ),
  };
}`,
`    session:
      getEncoderSession(
        gameId,
      ),
    telemetry:
      getEncoderTelemetry(
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

if (!text.includes('"/encoder-sessions/:gameId/telemetry"')) {
  const marker =
`  app.post(
    "/encoder-sessions/:gameId/start",`;

  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate encoder start route.");

  const route = `  app.get(
    "/encoder-sessions/:gameId/telemetry",
    async (request, reply) => {
      const params =
        request.params as {
          gameId?: string;
        };

      const gameId =
        params.gameId?.trim();

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          runtimeActive:
            snapshot.runtimeActive,
          session:
            snapshot.session,
          telemetry:
            snapshot.telemetry,
        },
      };
    },
  );

`;

  text = text.slice(0, idx) + route + text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type EncoderTelemetry =")) {
  const marker = "type StreamDestinationProfile = {";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate stream profile type.");

  const type = `type EncoderTelemetry = {
  gameId: string;
  health:
    | "IDLE"
    | "STARTING"
    | "HEALTHY"
    | "STALE"
    | "ERROR";
  frame: number | null;
  fps: number | null;
  bitrateKbps: number | null;
  totalSizeBytes: number | null;
  outTimeMs: number | null;
  speed: number | null;
  lastProgressAt: string | null;
  startedAt: string | null;
  lastError: string | null;
};

`;

  text = text.slice(0, idx) + type + text.slice(idx);
}

if (!text.includes("const [encoderTelemetry")) {
  const marker =
`  const [
    encoderSession,
    setEncoderSession,
  ] =
    useState<EncoderSession | null>(
      null,
    );`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate encoder session state.");
  }

  text = text.replace(
    marker,
`${marker}

  const [
    encoderTelemetry,
    setEncoderTelemetry,
  ] =
    useState<EncoderTelemetry | null>(
      null,
    );`
  );
}

if (!text.includes("/telemetry")) {
  const marker = "  async function startEncoderSession() {";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate encoder start function.");

  const hook =
'  useEffect(() => {\n' +
'    const normalized = gameId.trim();\n\n' +
'    if (\n' +
'      !normalized ||\n' +
'      !encoderSession ||\n' +
'      (\n' +
'        encoderSession.status !== "STARTING" &&\n' +
'        encoderSession.status !== "LIVE"\n' +
'      )\n' +
'    ) {\n' +
'      return;\n' +
'    }\n\n' +
'    const timer = window.setInterval(() => {\n' +
'      void fetch(\n' +
'        `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/telemetry`,\n' +
'        { cache: "no-store" },\n' +
'      )\n' +
'        .then((response) => response.json())\n' +
'        .then((json) => {\n' +
'          setEncoderSession(json?.data?.session ?? null);\n' +
'          setEncoderTelemetry(json?.data?.telemetry ?? null);\n' +
'        })\n' +
'        .catch(() => {\n' +
'          // Telemetry polling failure must not affect stream control.\n' +
'        });\n' +
'    }, 2000);\n\n' +
'    return () => window.clearInterval(timer);\n' +
'  }, [gameId, encoderSession?.status]);\n\n';

  text = text.slice(0, idx) + hook + text.slice(idx);
}

if (!text.includes("Publish Health")) {
  const marker =
`        {encoderSession?.lastError && (
          <p className="mt-3 text-xs text-red-300">
            Encoder status: {encoderSession.lastError}
          </p>
        )}`;

  if (!text.includes(marker)) {
    throw new Error("Unable to locate encoder status block.");
  }

  const addition =
    marker +
    '\n\n' +
    '        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">\n' +
    '          <div className="rounded border border-slate-800 p-3">\n' +
    '            <div className="text-xs text-slate-500">Publish Health</div>\n' +
    '            <div className="mt-1 font-semibold">{encoderTelemetry?.health ?? "IDLE"}</div>\n' +
    '          </div>\n' +
    '          <div className="rounded border border-slate-800 p-3">\n' +
    '            <div className="text-xs text-slate-500">FPS</div>\n' +
    '            <div className="mt-1 font-semibold">{encoderTelemetry?.fps ?? "--"}</div>\n' +
    '          </div>\n' +
    '          <div className="rounded border border-slate-800 p-3">\n' +
    '            <div className="text-xs text-slate-500">Bitrate</div>\n' +
    '            <div className="mt-1 font-semibold">{encoderTelemetry?.bitrateKbps != null ? `${encoderTelemetry.bitrateKbps} kbps` : "--"}</div>\n' +
    '          </div>\n' +
    '          <div className="rounded border border-slate-800 p-3">\n' +
    '            <div className="text-xs text-slate-500">Speed</div>\n' +
    '            <div className="mt-1 font-semibold">{encoderTelemetry?.speed != null ? `${encoderTelemetry.speed}x` : "--"}</div>\n' +
    '          </div>\n' +
    '        </div>\n\n' +
    '        {encoderTelemetry?.lastProgressAt && (\n' +
    '          <p className="mt-3 text-xs text-slate-500">\n' +
    '            Last encoder progress: {encoderTelemetry.lastProgressAt}\n' +
    '          </p>\n' +
    '        )}';

  text = text.replace(marker, addition);
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.6 — Encoder telemetry and publish health

FFmpeg now emits machine-readable progress through `-progress pipe:1`.

SportsOS tracks frame count, FPS, bitrate, output size, output time, speed, and last progress timestamp.

Publish health states:

```text
IDLE
STARTING
HEALTHY
STALE
ERROR
```

A healthy runtime with no progress update for more than 10 seconds is reported as `STALE`.

API:

```text
GET /encoder-sessions/:gameId/telemetry
```

The operator UI polls telemetry every 2 seconds while the encoder is starting or live.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.6 encoder telemetry / publish health", () => {
  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/encoderSessions.ts",
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

  it("enables FFmpeg progress output", () => {
    expect(runtime).toContain('"-progress"');
    expect(runtime).toContain('"pipe:1"');
  });

  it("tracks encoder metrics", () => {
    for (const field of [
      "frame",
      "fps",
      "bitrateKbps",
      "totalSizeBytes",
      "outTimeMs",
      "speed",
      "lastProgressAt",
    ]) {
      expect(runtime).toContain(field);
    }
  });

  it("detects stale publish health", () => {
    expect(runtime).toContain('"STALE"');
    expect(runtime).toContain("10000");
  });

  it("provides a telemetry endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/telemetry"',
    );
  });

  it("shows publish health in the operator UI", () => {
    expect(panel).toContain("Publish Health");
    expect(panel).toContain("Bitrate");
    expect(panel).toContain("Last encoder progress");
  });

  it("polls active-session telemetry every 2 seconds", () => {
    expect(panel).toContain("/telemetry");
    expect(panel).toContain("2000");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - FFmpeg progress telemetry"
echo "  - frame/FPS/bitrate/output-time/speed metrics"
echo "  - IDLE/STARTING/HEALTHY/STALE/ERROR publish health"
echo "  - 10-second stale detection"
echo "  - telemetry API"
echo "  - operator telemetry cards"
echo "  - 2-second active-session polling"
echo "  - Milestone 20.6 regression tests"
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
echo "  Milestone 20.7 - Encoder Recovery / Automatic Restart Policy"
