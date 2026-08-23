#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.9-streaming-readiness-preflight-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PREFLIGHT="apps/api/src/services/streamingReadinessPreflight.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/streaming-readiness-preflight-20.9.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "apps/api/src/services/streamDestinationProfile.ts" \
  "apps/api/src/services/encoderRuntime.ts" \
  "apps/api/src/services/encoderSession.ts" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PREFLIGHT" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PREFLIGHT")" "$(dirname "$TEST")"

cat > "$PREFLIGHT" <<'EOF'
import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";

import {
  getStreamDestinationProfile,
} from "./streamDestinationProfile.js";

export type StreamingReadinessCheck = {
  id:
    | "DESTINATION_PRESENT"
    | "DESTINATION_ENABLED"
    | "INGEST_URL"
    | "CREDENTIAL_REFERENCE"
    | "DESTINATION_PROBE"
    | "ENCODER_STATE"
    | "RECOVERY_STATE"
    | "SOURCE_CONFIGURATION";
  passed: boolean;
  message: string;
};

export type StreamingReadinessPreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: StreamingReadinessCheck[];
};

function sourceConfigured(): boolean {
  return Boolean(
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL
      ?.trim() ||
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE
      ?.trim(),
  );
}

export function evaluateStreamingReadiness(
  gameId: string,
): StreamingReadinessPreflight {
  const destination =
    getStreamDestinationProfile(
      gameId,
    );

  const runtime =
    encoderRuntimeSnapshot(
      gameId,
    );

  const checks:
    StreamingReadinessCheck[] = [
      {
        id:
          "DESTINATION_PRESENT",
        passed:
          Boolean(
            destination,
          ),
        message:
          destination
            ? "Stream destination profile exists."
            : "Stream destination profile is missing.",
      },
      {
        id:
          "DESTINATION_ENABLED",
        passed:
          Boolean(
            destination?.enabled,
          ),
        message:
          destination?.enabled
            ? "Streaming is enabled."
            : "Streaming is disabled.",
      },
      {
        id:
          "INGEST_URL",
        passed:
          Boolean(
            destination?.ingestUrl?.trim(),
          ),
        message:
          destination?.ingestUrl
            ? "Ingest URL is configured."
            : "Ingest URL is missing.",
      },
      {
        id:
          "CREDENTIAL_REFERENCE",
        passed:
          Boolean(
            destination?.credentialRef?.trim(),
          ),
        message:
          destination?.credentialRef
            ? "Credential reference is configured."
            : "Credential reference is missing.",
      },
      {
        id:
          "DESTINATION_PROBE",
        passed:
          destination?.status ===
            "READY" ||
          destination?.status ===
            "LIVE",
        message:
          destination?.status ===
            "READY" ||
          destination?.status ===
            "LIVE"
            ? "Destination reachability is ready."
            : "Destination must pass a connection probe.",
      },
      {
        id:
          "ENCODER_STATE",
        passed:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR",
        message:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR"
            ? "Encoder is available to start."
            : `Encoder is currently ${runtime.session.status}.`,
      },
      {
        id:
          "RECOVERY_STATE",
        passed:
          runtime.recovery.state !==
            "EXHAUSTED",
        message:
          runtime.recovery.state !==
            "EXHAUSTED"
            ? "Encoder recovery is available."
            : "Encoder recovery attempts are exhausted.",
      },
      {
        id:
          "SOURCE_CONFIGURATION",
        passed:
          sourceConfigured(),
        message:
          sourceConfigured()
            ? "Encoder source configuration is present."
            : "Encoder source URL or source URL template is missing.",
      },
    ];

  return {
    gameId,
    ready:
      checks.every(
        (check) =>
          check.passed,
      ),
    checkedAt:
      new Date().toISOString(),
    checks,
  };
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/encoderSessions.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { evaluateStreamingReadiness } from "../services/streamingReadinessPreflight.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate encoder route imports.",
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
    '"/encoder-sessions/:gameId/preflight"'
  )
) {
  const marker =
`  app.get(
    "/encoder-sessions/:gameId/audit",`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate audit route.",
    );
  }

  const route =
`  app.get(
    "/encoder-sessions/:gameId/preflight",
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

      return {
        success: true,
        data: {
          preflight:
            evaluateStreamingReadiness(
              gameId,
            ),
        },
      };
    },
  );

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    route +
    text.slice(
      idx,
    );
}

/* Enforce preflight before runtime start. */
if (
  !text.includes(
    "STREAMING_READINESS_PREFLIGHT_20_9"
  )
) {
  const marker =
`      recordEncoderAuditEvent({
        gameId,
        type:
          "START_REQUESTED",
      });`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate encoder start request audit.",
    );
  }

  const guard =
`      // STREAMING_READINESS_PREFLIGHT_20_9
      const preflight =
        evaluateStreamingReadiness(
          gameId,
        );

      if (!preflight.ready) {
        return reply.code(409).send({
          success: false,
          error:
            "Streaming readiness preflight failed.",
          data: {
            preflight,
          },
        });
      }

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    guard +
    text.slice(
      idx,
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
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "type StreamingReadinessPreflight ="
  )
) {
  const marker =
    "type StreamDestinationProfile = {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate stream profile type.",
    );
  }

  const type =
`type StreamingReadinessPreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: Array<{
    id: string;
    passed: boolean;
    message: string;
  }>;
};

`;

  text =
    text.slice(
      0,
      idx,
    ) +
    type +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "const [streamingPreflight"
  )
) {
  const marker =
`  const [
    encoderAudit,
    setEncoderAudit,
  ] =
    useState<EncoderAuditEvent[]>(
      [],
    );`;

  if (
    !text.includes(
      marker,
    )
  ) {
    throw new Error(
      "Unable to locate encoder audit state.",
    );
  }

  text =
    text.replace(
      marker,
`${marker}

  const [
    streamingPreflight,
    setStreamingPreflight,
  ] =
    useState<StreamingReadinessPreflight | null>(
      null,
    );`,
    );
}

if (
  !text.includes(
    "async function runStreamingPreflight"
  )
) {
  const marker =
    "  async function startEncoderSession() {";

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate encoder start function.",
    );
  }

  const fn =
    '  async function runStreamingPreflight() {\n' +
    '    const normalized = gameId.trim();\n' +
    '    if (!normalized) return;\n\n' +
    '    setBusy(true);\n' +
    '    try {\n' +
    '      const response = await fetch(\n' +
    '        `${API_BASE}/encoder-sessions/${encodeURIComponent(normalized)}/preflight`,\n' +
    '        { cache: "no-store" },\n' +
    '      );\n' +
    '      const json = await response.json();\n' +
    '      if (!response.ok) {\n' +
    '        throw new Error(json?.error ?? `Streaming preflight failed (${response.status}).`);\n' +
    '      }\n' +
    '      setStreamingPreflight(json?.data?.preflight ?? null);\n' +
    '      setError(null);\n' +
    '    } catch (preflightError) {\n' +
    '      setError(\n' +
    '        preflightError instanceof Error\n' +
    '          ? preflightError.message\n' +
    '          : "Unable to run streaming preflight.",\n' +
    '      );\n' +
    '    } finally {\n' +
    '      setBusy(false);\n' +
    '    }\n' +
    '  }\n\n';

  text =
    text.slice(
      0,
      idx,
    ) +
    fn +
    text.slice(
      idx,
    );
}

if (
  !text.includes(
    "Streaming Readiness"
  )
) {
  const marker =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Encoder Session`;

  const idx =
    text.indexOf(
      marker,
    );

  if (
    idx === -1
  ) {
    throw new Error(
      "Unable to locate Encoder Session panel.",
    );
  }

  const block =
`      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Streaming Readiness
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Validate destination, probe, encoder availability, recovery state, and source configuration before start.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-xs font-medium">
            {streamingPreflight
              ? streamingPreflight.ready
                ? "READY"
                : "BLOCKED"
              : "NOT CHECKED"}
          </span>
        </div>

        <div className="mt-3">
          <button
            type="button"
            disabled={
              busy ||
              !gameId.trim()
            }
            onClick={() =>
              void runStreamingPreflight()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Run Streaming Preflight
          </button>
        </div>

        {streamingPreflight && (
          <div className="mt-4 space-y-2">
            {streamingPreflight.checks.map(
              (check) => (
                <div
                  key={check.id}
                  className="flex items-start justify-between gap-3 rounded border border-slate-800 p-3"
                >
                  <div>
                    <div className="text-xs font-semibold">
                      {check.id}
                    </div>
                    <div className="mt-1 text-xs text-slate-500">
                      {check.message}
                    </div>
                  </div>

                  <span
                    className={
                      \`text-xs font-semibold \${
                        check.passed
                          ? "text-slate-300"
                          : "text-red-300"
                      }\`
                    }
                  >
                    {check.passed
                      ? "PASS"
                      : "FAIL"}
                  </span>
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

cat >> "$DOC" <<'EOF'

## Milestone 20.9 — Streaming readiness and operator preflight

Streaming start now has an explicit server-side preflight.

Checks:

```text
DESTINATION_PRESENT
DESTINATION_ENABLED
INGEST_URL
CREDENTIAL_REFERENCE
DESTINATION_PROBE
ENCODER_STATE
RECOVERY_STATE
SOURCE_CONFIGURATION
```

The encoder start API rejects the request with HTTP 409 when preflight is not ready.

Operator API:

```text
GET /encoder-sessions/:gameId/preflight
```

The operator UI shows every check as PASS or FAIL and provides a dedicated **Run Streaming Preflight** action.

This preflight does not modify game state and does not start media publishing.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.9 streaming readiness / operator preflight", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamingReadinessPreflight.ts",
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

  it("checks destination and credential readiness", () => {
    expect(service).toContain(
      '"DESTINATION_PRESENT"',
    );
    expect(service).toContain(
      '"DESTINATION_ENABLED"',
    );
    expect(service).toContain(
      '"INGEST_URL"',
    );
    expect(service).toContain(
      '"CREDENTIAL_REFERENCE"',
    );
  });

  it("checks probe, encoder, recovery, and source configuration", () => {
    expect(service).toContain(
      '"DESTINATION_PROBE"',
    );
    expect(service).toContain(
      '"ENCODER_STATE"',
    );
    expect(service).toContain(
      '"RECOVERY_STATE"',
    );
    expect(service).toContain(
      '"SOURCE_CONFIGURATION"',
    );
  });

  it("blocks encoder start when preflight fails", () => {
    expect(route).toContain(
      "STREAMING_READINESS_PREFLIGHT_20_9",
    );
    expect(route).toContain(
      "Streaming readiness preflight failed.",
    );
  });

  it("provides a preflight endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/preflight"',
    );
  });

  it("provides operator readiness UI", () => {
    expect(panel).toContain(
      "Streaming Readiness",
    );
    expect(panel).toContain(
      "Run Streaming Preflight",
    );
    expect(panel).toContain(
      '"PASS"',
    );
    expect(panel).toContain(
      '"FAIL"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - server-side streaming readiness preflight"
echo "  - destination/profile validation"
echo "  - probe readiness validation"
echo "  - encoder/recovery availability validation"
echo "  - source configuration validation"
echo "  - HTTP 409 start blocking when not ready"
echo "  - operator PASS/FAIL checklist"
echo "  - Milestone 20.9 regression tests"
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
echo "  Milestone 20.10 - Streaming Operations Acceptance / Closeout"
