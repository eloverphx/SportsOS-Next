#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.3-stream-destination-readiness-probe-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/streamDestinationProfile.ts"
PROBE="apps/api/src/services/streamDestinationProbe.ts"
ROUTE="apps/api/src/routes/streamDestinationProfiles.ts"
PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
TEST="packages/core/test/stream-destination-readiness-probe-20.3.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "$SERVICE" \
  "$ROUTE" \
  "$PANEL"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$PROBE" "$ROUTE" "$PANEL" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PROBE")" "$(dirname "$TEST")"

cat > "$PROBE" <<'EOF'
import net from "node:net";

export type StreamDestinationProbeResult = {
  reachable: boolean;
  host: string | null;
  port: number | null;
  checkedAt: string;
  latencyMs: number | null;
  error: string | null;
};

function defaultPort(
  protocol: "RTMP" | "SRT",
  url: URL,
): number {
  if (url.port) {
    return Number(url.port);
  }

  if (protocol === "RTMP") {
    return 1935;
  }

  return 9000;
}

export async function probeStreamDestination(input: {
  protocol: "RTMP" | "SRT";
  ingestUrl: string;
  timeoutMs?: number;
}): Promise<StreamDestinationProbeResult> {
  const checkedAt =
    new Date().toISOString();

  let parsed: URL;

  try {
    parsed =
      new URL(
        input.ingestUrl,
      );
  } catch {
    return {
      reachable: false,
      host: null,
      port: null,
      checkedAt,
      latencyMs: null,
      error:
        "Invalid ingest URL.",
    };
  }

  const host =
    parsed.hostname;

  const port =
    defaultPort(
      input.protocol,
      parsed,
    );

  const timeoutMs =
    Math.max(
      500,
      Math.min(
        input.timeoutMs ??
          3000,
        10000,
      ),
    );

  const startedAt =
    Date.now();

  return await new Promise(
    (resolve) => {
      const socket =
        net.createConnection({
          host,
          port,
        });

      let settled =
        false;

      function finish(
        result:
          StreamDestinationProbeResult,
      ) {
        if (settled) {
          return;
        }

        settled =
          true;

        socket.destroy();

        resolve(
          result,
        );
      }

      socket.setTimeout(
        timeoutMs,
      );

      socket.once(
        "connect",
        () => {
          finish({
            reachable:
              true,
            host,
            port,
            checkedAt,
            latencyMs:
              Date.now() -
              startedAt,
            error:
              null,
          });
        },
      );

      socket.once(
        "timeout",
        () => {
          finish({
            reachable:
              false,
            host,
            port,
            checkedAt,
            latencyMs:
              null,
            error:
              "Connection probe timed out.",
          });
        },
      );

      socket.once(
        "error",
        (error) => {
          finish({
            reachable:
              false,
            host,
            port,
            checkedAt,
            latencyMs:
              null,
            error:
              error.message,
          });
        },
      );
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/services/streamDestinationProfile.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("lastProbeAt:")) {
  text = text.replace(
`  lastError: string | null;
  updatedAt: string;`,
`  lastError: string | null;
  lastProbeAt: string | null;
  lastProbeLatencyMs: number | null;
  updatedAt: string;`
  );
}

if (!text.includes("updateStreamDestinationProbeResult")) {
  const marker =
`export function deleteStreamDestinationProfile(`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate stream destination delete function.",
    );
  }

  const fn =
`export function updateStreamDestinationProbeResult(input: {
  gameId: string;
  reachable: boolean;
  checkedAt: string;
  latencyMs: number | null;
  error: string | null;
}): StreamDestinationProfile | null {
  const existing =
    getStreamDestinationProfile(
      input.gameId,
    );

  if (!existing) {
    return null;
  }

  const profile:
    StreamDestinationProfile = {
      ...existing,
      status:
        input.reachable
          ? "READY"
          : "ERROR",
      lastError:
        input.error,
      lastProbeAt:
        input.checkedAt,
      lastProbeLatencyMs:
        input.latencyMs,
      updatedAt:
        new Date().toISOString(),
    };

  store.profiles =
    store.profiles.filter(
      (item) =>
        item.gameId !==
        input.gameId,
    );

  store.profiles.push(
    profile,
  );

  persistStore();

  return {
    ...profile,
  };
}

`;

  text =
    text.slice(0, idx) +
    fn +
    text.slice(idx);
}

if (
  !text.includes(
    "lastProbeAt:"
  ) ||
  !text.includes(
    "lastProbeLatencyMs:"
  )
) {
  throw new Error(
    "Probe fields missing after patch.",
  );
}

if (
  !text.includes(
    "lastProbeAt:\n        existing?.lastProbeAt"
  )
) {
  text = text.replace(
`      lastError:
        enabled &&
        !configured
          ? "Enabled stream destination requires ingestUrl and credentialRef."
          : null,
      updatedAt:`,
`      lastError:
        enabled &&
        !configured
          ? "Enabled stream destination requires ingestUrl and credentialRef."
          : null,
      lastProbeAt:
        existing?.lastProbeAt ??
        null,
      lastProbeLatencyMs:
        existing?.lastProbeLatencyMs ??
        null,
      updatedAt:`
  );
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/streamDestinationProfiles.ts";
let text = fs.readFileSync(file, "utf8");

const probeImport =
  'import { probeStreamDestination } from "../services/streamDestinationProbe.js";';

if (!text.includes(probeImport)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate stream route imports.",
    );
  }

  text =
    text.replace(
      imports[0],
      imports[0] +
        probeImport +
        "\n",
    );
}

if (!text.includes("updateStreamDestinationProbeResult")) {
  text = text.replace(
`  upsertStreamDestinationProfile,`,
`  upsertStreamDestinationProfile,
  updateStreamDestinationProbeResult,`
  );
}

if (!text.includes('"/stream-destinations/:gameId/probe"')) {
  const marker =
`  app.delete(
    "/stream-destinations/:gameId",`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate stream delete route.",
    );
  }

  const route =
`  app.post(
    "/stream-destinations/:gameId/probe",
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

      const profile =
        getStreamDestinationProfile(
          gameId,
        );

      if (
        !profile ||
        !profile.enabled ||
        !profile.ingestUrl
      ) {
        return reply.code(409).send({
          success: false,
          error:
            "Enabled stream destination with ingest URL is required before probing.",
        });
      }

      const result =
        await probeStreamDestination({
          protocol:
            profile.protocol,
          ingestUrl:
            profile.ingestUrl,
        });

      const updated =
        updateStreamDestinationProbeResult({
          gameId,
          reachable:
            result.reachable,
          checkedAt:
            result.checkedAt,
          latencyMs:
            result.latencyMs,
          error:
            result.error,
        });

      return {
        success: true,
        data: {
          probe:
            result,
          profile:
            updated,
        },
      };
    },
  );

`;

  text =
    text.slice(0, idx) +
    route +
    text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("lastProbeAt:")) {
  text = text.replace(
`  lastError: string | null;
  updatedAt: string;
};`,
`  lastError: string | null;
  lastProbeAt: string | null;
  lastProbeLatencyMs: number | null;
  updatedAt: string;
};`
  );
}

if (!text.includes("async function probeDestination")) {
  const marker =
`  async function resetProfile() {`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate resetProfile.",
    );
  }

  const fn =
`  async function probeDestination() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before probing the stream destination.",
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          \`${API_BASE}/stream-destinations/\${encodeURIComponent(normalized)}/probe\`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Destination probe failed (\${response.status}).\`,
        );
      }

      setProfile(
        json?.data?.profile ??
        null,
      );

      setError(
        null,
      );
    } catch (probeError) {
      setError(
        probeError instanceof Error
          ? probeError.message
          : "Unable to probe stream destination.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

`;

  text =
    text.slice(0, idx) +
    fn +
    text.slice(idx);
}

if (!text.includes("Probe Destination")) {
  const marker =
`        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim()
          }
          onClick={() =>
            void resetProfile()
          }`;

  const idx = text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate reset button.",
    );
  }

  const button =
`        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim() ||
            !enabled ||
            !validation.valid
          }
          onClick={() =>
            void probeDestination()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Probe Destination
        </button>

`;

  text =
    text.slice(0, idx) +
    button +
    text.slice(idx);
}

if (!text.includes("Last probe")) {
  const marker =
`        {profile?.lastError && (
          <p className="mt-2 text-xs text-red-300">
            Server status: {profile.lastError}
          </p>
        )}`;

  if (!text.includes(marker)) {
    throw new Error(
      "Unable to locate server status block.",
    );
  }

  const addition =
`${marker}

        {profile?.lastProbeAt && (
          <p className="mt-2 text-xs text-slate-500">
            Last probe: {profile.lastProbeAt}
            {profile.lastProbeLatencyMs != null
              ? \` · \${profile.lastProbeLatencyMs} ms\`
              : ""}
          </p>
        )}`;

  text =
    text.replace(
      marker,
      addition,
    );
}

fs.writeFileSync(file, text);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.3 — Destination readiness and connection probe

Operators can now run a safe connection probe against the configured ingest endpoint.

The probe:

- resolves the configured host and port from the ingest URL
- opens a short TCP connection
- records reachability
- records connection latency
- records probe timestamp
- updates destination state to `READY` or `ERROR`

The probe does not:

- send a stream key
- resolve or transmit `credentialRef`
- publish media
- start an encoder
- create a live stream

Default ports:

```text
RTMP: 1935
SRT: 9000
```

Explicit URL ports override the defaults.

The readiness probe is a transport reachability check, not proof that upstream authentication or publishing will succeed.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.3 stream destination readiness / connection probe", () => {
  const probe =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationProbe.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const profile =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamDestinationProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/streamDestinationProfiles.ts",
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

  it("uses a TCP reachability probe", () => {
    expect(probe).toContain(
      "net.createConnection",
    );

    expect(probe).toContain(
      "setTimeout",
    );
  });

  it("uses protocol default ports", () => {
    expect(probe).toContain(
      "1935",
    );

    expect(probe).toContain(
      "9000",
    );
  });

  it("persists probe readiness", () => {
    expect(profile).toContain(
      "lastProbeAt",
    );

    expect(profile).toContain(
      "lastProbeLatencyMs",
    );

    expect(profile).toContain(
      'input.reachable\n          ? "READY"\n          : "ERROR"',
    );
  });

  it("provides an operator probe route", () => {
    expect(route).toContain(
      '"/stream-destinations/:gameId/probe"',
    );

    expect(route).toContain(
      "probeStreamDestination",
    );
  });

  it("provides a dashboard probe control", () => {
    expect(panel).toContain(
      "Probe Destination",
    );

    expect(panel).toContain(
      "Last probe",
    );
  });

  it("does not transmit credential references in the probe service", () => {
    expect(probe).not.toContain(
      "credentialRef",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.3 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - server-side RTMP/SRT endpoint reachability probe"
echo "  - TCP latency measurement"
echo "  - READY / ERROR state updates"
echo "  - last probe timestamp"
echo "  - dashboard Probe Destination control"
echo "  - no credential transmission"
echo "  - no media publishing"
echo "  - Milestone 20.3 regression tests"
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
echo "  Milestone 20.4 - Encoder Session Model / Start-Stop Control Foundation"
