#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.3-literal-safe-dashboard-repair-${STAMP}"

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

# Recreate the probe service if the failed installer did not get that far.
if [[ ! -f "$PROBE" ]]; then
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
fi

node <<'NODE'
const fs = require("fs");

const serviceFile =
  "apps/api/src/services/streamDestinationProfile.ts";
let service =
  fs.readFileSync(serviceFile, "utf8");

if (!service.includes("lastProbeAt:")) {
  service = service.replace(
`  lastError: string | null;
  updatedAt: string;`,
`  lastError: string | null;
  lastProbeAt: string | null;
  lastProbeLatencyMs: number | null;
  updatedAt: string;`
  );
}

if (!service.includes("updateStreamDestinationProbeResult")) {
  const marker =
    "export function deleteStreamDestinationProfile(";
  const idx =
    service.indexOf(marker);

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

  service =
    service.slice(0, idx) +
    fn +
    service.slice(idx);
}

if (
  !service.includes(
    "lastProbeAt:\n        existing?.lastProbeAt"
  )
) {
  service = service.replace(
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

fs.writeFileSync(serviceFile, service);
NODE

node <<'NODE'
const fs = require("fs");

const routeFile =
  "apps/api/src/routes/streamDestinationProfiles.ts";
let route =
  fs.readFileSync(routeFile, "utf8");

const probeImport =
  'import { probeStreamDestination } from "../services/streamDestinationProbe.js";';

if (!route.includes(probeImport)) {
  const imports =
    route.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate stream route imports.",
    );
  }

  route =
    route.replace(
      imports[0],
      imports[0] +
        probeImport +
        "\n",
    );
}

if (!route.includes("updateStreamDestinationProbeResult")) {
  route =
    route.replace(
      "  upsertStreamDestinationProfile,",
      "  upsertStreamDestinationProfile,\n  updateStreamDestinationProbeResult,",
    );
}

if (!route.includes('"/stream-destinations/:gameId/probe"')) {
  const marker =
`  app.delete(
    "/stream-destinations/:gameId",`;

  const idx =
    route.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate stream delete route.",
    );
  }

  const block =
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

  route =
    route.slice(0, idx) +
    block +
    route.slice(idx);
}

fs.writeFileSync(routeFile, route);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

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
    "  async function resetProfile() {";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate resetProfile.",
    );
  }

  const fn =
    '  async function probeDestination() {\n' +
    '    const normalized =\n' +
    '      gameId.trim();\n\n' +
    '    if (!normalized) {\n' +
    '      setError(\n' +
    '        "Enter a game ID before probing the stream destination.",\n' +
    '      );\n' +
    '      return;\n' +
    '    }\n\n' +
    '    setBusy(true);\n\n' +
    '    try {\n' +
    '      const response =\n' +
    '        await fetch(\n' +
    '          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}/probe`,\n' +
    '          {\n' +
    '            method: "POST",\n' +
    '          },\n' +
    '        );\n\n' +
    '      const json =\n' +
    '        await response.json();\n\n' +
    '      if (!response.ok) {\n' +
    '        throw new Error(\n' +
    '          json?.error ??\n' +
    '          `Destination probe failed (${response.status}).`,\n' +
    '        );\n' +
    '      }\n\n' +
    '      setProfile(\n' +
    '        json?.data?.profile ??\n' +
    '        null,\n' +
    '      );\n\n' +
    '      setError(null);\n' +
    '    } catch (probeError) {\n' +
    '      setError(\n' +
    '        probeError instanceof Error\n' +
    '          ? probeError.message\n' +
    '          : "Unable to probe stream destination.",\n' +
    '      );\n' +
    '    } finally {\n' +
    '      setBusy(false);\n' +
    '    }\n' +
    '  }\n\n';

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

  const idx =
    text.indexOf(marker);

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
    marker +
    '\n\n' +
    '        {profile?.lastProbeAt && (\n' +
    '          <p className="mt-2 text-xs text-slate-500">\n' +
    '            Last probe: {profile.lastProbeAt}\n' +
    '            {profile.lastProbeLatencyMs != null\n' +
    '              ? ` · ${profile.lastProbeLatencyMs} ms`\n' +
    '              : ""}\n' +
    '          </p>\n' +
    '        )}';

  text =
    text.replace(
      marker,
      addition,
    );
}

for (const required of [
  "async function probeDestination",
  "/probe",
  "Probe Destination",
  "Last probe",
  "lastProbeLatencyMs",
]) {
  if (!text.includes(required)) {
    throw new Error(
      `20.3 dashboard verification failed: ${required}`,
    );
  }
}

fs.writeFileSync(file, text);
NODE

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
  });

  it("uses protocol default ports", () => {
    expect(probe).toContain("1935");
    expect(probe).toContain("9000");
  });

  it("persists probe readiness", () => {
    expect(profile).toContain(
      "lastProbeAt",
    );

    expect(profile).toContain(
      "lastProbeLatencyMs",
    );
  });

  it("provides an operator probe route", () => {
    expect(route).toContain(
      '"/stream-destinations/:gameId/probe"',
    );
  });

  it("provides dashboard probe controls", () => {
    expect(panel).toContain(
      "Probe Destination",
    );

    expect(panel).toContain(
      "Last probe",
    );
  });

  it("does not transmit credentials from the probe service", () => {
    expect(probe).not.toContain(
      "credentialRef",
    );
  });
});
EOF

if [[ -f "$DOC" ]] && ! grep -q "Milestone 20.3 — Destination readiness" "$DOC"; then
cat >> "$DOC" <<'EOF'

## Milestone 20.3 — Destination readiness and connection probe

Operators can run a safe TCP reachability check against the configured ingest endpoint.

The probe records readiness, latency, timestamp, and error state without transmitting credentials or publishing media.
EOF
fi

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.3 literal-safe repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - no Node evaluation of dashboard \${API_BASE} template literals"
echo "  - restores probe service/API if previous installer stopped early"
echo "  - adds dashboard Probe Destination action safely"
echo "  - records last probe timestamp/latency"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
