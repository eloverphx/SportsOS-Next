#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.2-stream-destination-operator-ui-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx"
PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/stream-destination-operator-ui-20.2.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "apps/api/src/routes/streamDestinationProfiles.ts" \
  "$PAGE"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PANEL" "$PAGE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PANEL")" "$(dirname "$TEST")"

cat > "$PANEL" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type StreamProtocol =
  | "RTMP"
  | "SRT";

type StreamLatencyMode =
  | "NORMAL"
  | "LOW"
  | "ULTRA_LOW";

type StreamDestinationProfile = {
  gameId: string;
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string | null;
  streamName: string | null;
  credentialRef: string | null;
  latencyMode: StreamLatencyMode;
  status:
    | "DISABLED"
    | "CONFIGURED"
    | "READY"
    | "LIVE"
    | "ERROR";
  lastError: string | null;
  updatedAt: string;
};

function validateDestination(input: {
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string;
  credentialRef: string;
}): {
  valid: boolean;
  message: string;
} {
  if (!input.enabled) {
    return {
      valid: true,
      message:
        "Streaming is disabled.",
    };
  }

  const ingestUrl =
    input.ingestUrl.trim();

  const credentialRef =
    input.credentialRef.trim();

  if (!ingestUrl) {
    return {
      valid: false,
      message:
        "An ingest URL is required when streaming is enabled.",
    };
  }

  if (
    input.protocol ===
      "RTMP" &&
    !/^rtmps?:\/\//i.test(
      ingestUrl,
    )
  ) {
    return {
      valid: false,
      message:
        "RTMP destinations must begin with rtmp:// or rtmps://.",
    };
  }

  if (
    input.protocol ===
      "SRT" &&
    !/^srt:\/\//i.test(
      ingestUrl,
    )
  ) {
    return {
      valid: false,
      message:
        "SRT destinations must begin with srt://.",
    };
  }

  if (!credentialRef) {
    return {
      valid: false,
      message:
        "A credential reference is required when streaming is enabled.",
    };
  }

  return {
    valid: true,
    message:
      "Destination configuration is valid.",
  };
}

export function StreamDestinationPanel() {
  const [gameId, setGameId] =
    useState("");

  const [profile, setProfile] =
    useState<StreamDestinationProfile | null>(
      null,
    );

  const [enabled, setEnabled] =
    useState(false);

  const [protocol, setProtocol] =
    useState<StreamProtocol>(
      "RTMP",
    );

  const [ingestUrl, setIngestUrl] =
    useState("");

  const [streamName, setStreamName] =
    useState("");

  const [credentialRef, setCredentialRef] =
    useState("");

  const [latencyMode, setLatencyMode] =
    useState<StreamLatencyMode>(
      "NORMAL",
    );

  const [busy, setBusy] =
    useState(false);

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const loadProfile =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setProfile(
            null,
          );
          return;
        }

        const response =
          await fetch(
            `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
            {
              cache:
                "no-store",
            },
          );

        if (!response.ok) {
          return;
        }

        const json =
          await response.json();

        const nextProfile =
          json?.data?.profile ??
          null;

        setProfile(
          nextProfile,
        );

        setEnabled(
          nextProfile?.enabled ??
          false,
        );

        setProtocol(
          nextProfile?.protocol ??
          "RTMP",
        );

        setIngestUrl(
          nextProfile?.ingestUrl ??
          "",
        );

        setStreamName(
          nextProfile?.streamName ??
          "",
        );

        setCredentialRef(
          nextProfile?.credentialRef ??
          "",
        );

        setLatencyMode(
          nextProfile?.latencyMode ??
          "NORMAL",
        );
      },
      [],
    );

  useEffect(() => {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void loadProfile(
            normalized,
          );
        },
        350,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    loadProfile,
  ]);

  const validation =
    useMemo(
      () =>
        validateDestination({
          enabled,
          protocol,
          ingestUrl,
          credentialRef,
        }),
      [
        enabled,
        protocol,
        ingestUrl,
        credentialRef,
      ],
    );

  async function saveProfile() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before saving stream settings.",
      );
      return;
    }

    if (!validation.valid) {
      setError(
        validation.message,
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                enabled,
                protocol,
                ingestUrl:
                  ingestUrl.trim() ||
                  null,
                streamName:
                  streamName.trim() ||
                  null,
                credentialRef:
                  credentialRef.trim() ||
                  null,
                latencyMode,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Stream destination save failed (${response.status}).`,
        );
      }

      setProfile(
        json?.data?.profile ??
        null,
      );

      setError(
        null,
      );
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to save stream destination.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function resetProfile() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/stream-destinations/${encodeURIComponent(normalized)}`,
          {
            method:
              "DELETE",
          },
        );

      if (!response.ok) {
        throw new Error(
          `Stream destination reset failed (${response.status}).`,
        );
      }

      setProfile(
        null,
      );

      setEnabled(
        false,
      );

      setProtocol(
        "RTMP",
      );

      setIngestUrl(
        "",
      );

      setStreamName(
        "",
      );

      setCredentialRef(
        "",
      );

      setLatencyMode(
        "NORMAL",
      );

      setError(
        null,
      );
    } catch (resetError) {
      setError(
        resetError instanceof Error
          ? resetError.message
          : "Unable to reset stream destination.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Stream Destination
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Configure the encoder destination for a game without exposing raw stream credentials publicly.
          </p>
        </div>

        {profile && (
          <span className="rounded border border-slate-700 px-3 py-1 text-xs">
            {profile.status}
          </span>
        )}
      </div>

      <div className="mt-5">
        <label className="text-xs text-slate-500">
          Game ID
        </label>
        <input
          value={gameId}
          onChange={(event) =>
            setGameId(
              event.target.value,
            )
          }
          placeholder="Game ID"
          className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(event) =>
              setEnabled(
                event.target.checked,
              )
            }
          />
          Streaming enabled
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Protocol
          </span>
          <select
            value={protocol}
            onChange={(event) =>
              setProtocol(
                event.target.value as
                  StreamProtocol,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="RTMP">
              RTMP / RTMPS
            </option>
            <option value="SRT">
              SRT
            </option>
          </select>
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Latency mode
          </span>
          <select
            value={latencyMode}
            onChange={(event) =>
              setLatencyMode(
                event.target.value as
                  StreamLatencyMode,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="NORMAL">
              Normal
            </option>
            <option value="LOW">
              Low
            </option>
            <option value="ULTRA_LOW">
              Ultra Low
            </option>
          </select>
        </label>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <label className="text-sm md:col-span-2">
          <span className="text-xs text-slate-500">
            Ingest URL
          </span>
          <input
            value={ingestUrl}
            onChange={(event) =>
              setIngestUrl(
                event.target.value,
              )
            }
            placeholder={
              protocol ===
                "RTMP"
                ? "rtmps://..."
                : "srt://..."
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Stream name
          </span>
          <input
            value={streamName}
            onChange={(event) =>
              setStreamName(
                event.target.value,
              )
            }
            placeholder="Game stream"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Credential reference
          </span>
          <input
            value={credentialRef}
            onChange={(event) =>
              setCredentialRef(
                event.target.value,
              )
            }
            placeholder="secret://..."
            autoComplete="off"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
          <span className="mt-1 block text-xs text-slate-600">
            Reference only. Do not paste a raw stream key here.
          </span>
        </label>
      </div>

      <div className="mt-4 rounded-lg border border-slate-800 p-3">
        <div className="text-sm font-semibold">
          Configuration Validation
        </div>
        <p
          className={
            `mt-1 text-xs ${
              validation.valid
                ? "text-slate-500"
                : "text-red-300"
            }`
          }
        >
          {validation.message}
        </p>

        {profile?.lastError && (
          <p className="mt-2 text-xs text-red-300">
            Server status: {profile.lastError}
          </p>
        )}
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-3">
        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim() ||
            !validation.valid
          }
          onClick={() =>
            void saveProfile()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Save Stream Destination
        </button>

        <button
          type="button"
          disabled={
            busy ||
            !gameId.trim()
          }
          onClick={() =>
            void resetProfile()
          }
          className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
        >
          Reset Stream Destination
        </button>
      </div>
    </section>
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

const importLine =
  'import { StreamDestinationPanel } from "./StreamDestinationPanel";';

if (!text.includes(importLine)) {
  const imports =
    text.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate scoreboard operations imports.",
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
    "<StreamDestinationPanel />"
  )
) {
  const broadcastMarker =
    "<BroadcastSessionPanel />";

  if (
    text.includes(
      broadcastMarker,
    )
  ) {
    text =
      text.replace(
        broadcastMarker,
        broadcastMarker +
          "\n      <StreamDestinationPanel />",
      );
  } else {
    const closeMain =
      text.lastIndexOf(
        "</main>",
      );

    if (
      closeMain === -1
    ) {
      throw new Error(
        "Unable to locate operations page main container.",
      );
    }

    text =
      text.slice(
        0,
        closeMain,
      ) +
      "      <StreamDestinationPanel />\n" +
      text.slice(
        closeMain,
      );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.2 — Stream destination operator UI and validation

Scoreboard Operations now includes a Stream Destination panel.

Operators can:

- select a game
- enable or disable streaming
- choose RTMP/RTMPS or SRT
- choose latency mode
- configure ingest URL
- configure a display stream name
- provide a server-side credential reference
- save/reset the destination

Client validation requires:

- RTMP ingest URLs to begin with `rtmp://` or `rtmps://`
- SRT ingest URLs to begin with `srt://`
- a credential reference whenever streaming is enabled

The UI explicitly warns operators not to paste raw stream keys into the credential-reference field.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.2 stream destination operator UI / validation", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("supports RTMP and SRT configuration", () => {
    expect(panel).toContain(
      "RTMP / RTMPS",
    );

    expect(panel).toContain(
      "SRT",
    );
  });

  it("validates protocol-specific ingest URLs", () => {
    expect(panel).toContain(
      "rtmps?:",
    );

    expect(panel).toContain(
      "srt:",
    );

    expect(panel).toContain(
      "validateDestination",
    );
  });

  it("requires a credential reference when enabled", () => {
    expect(panel).toContain(
      "A credential reference is required",
    );

    expect(panel).toContain(
      "Do not paste a raw stream key here.",
    );
  });

  it("provides save and reset actions", () => {
    expect(panel).toContain(
      "Save Stream Destination",
    );

    expect(panel).toContain(
      "Reset Stream Destination",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "StreamDestinationPanel",
    );

    expect(page).toContain(
      "<StreamDestinationPanel />",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.2 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - Stream Destination operator panel"
echo "  - RTMP/RTMPS + SRT selection"
echo "  - latency mode selection"
echo "  - ingest URL validation"
echo "  - credentialRef requirement"
echo "  - raw stream-key warning"
echo "  - save/reset controls"
echo "  - scoreboard operations integration"
echo "  - Milestone 20.2 regression tests"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 20.3 - Stream Destination Readiness / Connection Probe"
