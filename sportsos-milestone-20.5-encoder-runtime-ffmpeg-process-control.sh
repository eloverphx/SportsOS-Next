#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-20.5-ffmpeg-runtime-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SESSION="apps/api/src/services/encoderSession.ts"
DESTINATION="apps/api/src/services/streamDestinationProfile.ts"
ROUTE="apps/api/src/routes/encoderSessions.ts"
RUNTIME="apps/api/src/services/encoderRuntime.ts"
CREDENTIALS="apps/api/src/services/streamCredentialResolver.ts"
TEST="packages/core/test/encoder-runtime-ffmpeg-20.5.test.ts"
DOC="docs/STREAMING-OPERATIONS.md"

for required in \
  ".git" \
  "$SESSION" \
  "$DESTINATION" \
  "$ROUTE"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SESSION" "$ROUTE" "$RUNTIME" "$CREDENTIALS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$RUNTIME")" "$(dirname "$TEST")"

cat > "$CREDENTIALS" <<'EOF'
export function resolveStreamCredential(
  credentialRef: string | null,
): string {
  const normalized =
    credentialRef?.trim() ??
    "";

  if (!normalized) {
    throw new Error(
      "Stream credential reference is required.",
    );
  }

  if (
    !normalized.startsWith(
      "env://",
    )
  ) {
    throw new Error(
      "Unsupported credential reference. Milestone 20.5 supports env://NAME only.",
    );
  }

  const variableName =
    normalized.slice(
      "env://".length,
    );

  if (
    !/^[A-Z_][A-Z0-9_]*$/.test(
      variableName,
    )
  ) {
    throw new Error(
      "Invalid environment credential reference.",
    );
  }

  const secret =
    process.env[
      variableName
    ]?.trim();

  if (!secret) {
    throw new Error(
      `Credential environment variable ${variableName} is not configured.`,
    );
  }

  return secret;
}
EOF

cat > "$RUNTIME" <<'EOF'
import {
  spawn,
  type ChildProcessWithoutNullStreams,
} from "node:child_process";

import {
  getEncoderSession,
  markEncoderError,
  markEncoderLive,
  markEncoderStopped,
} from "./encoderSession.js";

import type {
  StreamDestinationProfile,
} from "./streamDestinationProfile.js";

import {
  resolveStreamCredential,
} from "./streamCredentialResolver.js";

type RuntimeEntry = {
  process:
    ChildProcessWithoutNullStreams;
  stopRequested:
    boolean;
  liveTimer:
    NodeJS.Timeout | null;
};

const runtimes =
  new Map<
    string,
    RuntimeEntry
  >();

function resolveSourceUrl(
  gameId: string,
): string {
  const template =
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE
      ?.trim();

  const direct =
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL
      ?.trim();

  const value =
    template
      ? template.replaceAll(
          "{gameId}",
          encodeURIComponent(
            gameId,
          ),
        )
      : direct;

  if (!value) {
    throw new Error(
      "SPORTSOS_ENCODER_SOURCE_URL or SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE is required.",
    );
  }

  return value;
}

function buildOutputUrl(
  destination:
    StreamDestinationProfile,
  secret: string,
): string {
  const ingestUrl =
    destination.ingestUrl?.trim();

  if (!ingestUrl) {
    throw new Error(
      "Stream ingest URL is required.",
    );
  }

  if (
    destination.protocol ===
    "RTMP"
  ) {
    return (
      ingestUrl.replace(
        /\/+$/,
        "",
      ) +
      "/" +
      encodeURIComponent(
        secret,
      )
    );
  }

  const url =
    new URL(
      ingestUrl,
    );

  url.searchParams.set(
    "passphrase",
    secret,
  );

  return url.toString();
}

function buildFfmpegArgs(input: {
  destination:
    StreamDestinationProfile;
  sourceUrl: string;
  outputUrl: string;
}): string[] {
  const args = [
    "-hide_banner",
    "-nostdin",
    "-loglevel",
    "warning",
    "-i",
    input.sourceUrl,
    "-map",
    "0:v?",
    "-map",
    "0:a?",
    "-c",
    "copy",
  ];

  if (
    input.destination.protocol ===
    "RTMP"
  ) {
    args.push(
      "-f",
      "flv",
    );
  } else {
    args.push(
      "-f",
      "mpegts",
    );
  }

  args.push(
    input.outputUrl,
  );

  return args;
}

function sanitizedMessage(
  error: unknown,
): string {
  if (
    error instanceof Error
  ) {
    return error.message;
  }

  return "Encoder runtime error.";
}

export function isEncoderRuntimeActive(
  gameId: string,
): boolean {
  return runtimes.has(
    gameId,
  );
}

export async function startEncoderRuntime(input: {
  gameId: string;
  destination:
    StreamDestinationProfile;
}): Promise<void> {
  if (
    runtimes.has(
      input.gameId,
    )
  ) {
    return;
  }

  const sourceUrl =
    resolveSourceUrl(
      input.gameId,
    );

  const secret =
    resolveStreamCredential(
      input.destination
        .credentialRef,
    );

  const outputUrl =
    buildOutputUrl(
      input.destination,
      secret,
    );

  const ffmpegPath =
    process.env
      .SPORTSOS_FFMPEG_PATH
      ?.trim() ||
    "ffmpeg";

  const args =
    buildFfmpegArgs({
      destination:
        input.destination,
      sourceUrl,
      outputUrl,
    });

  const child =
    spawn(
      ffmpegPath,
      args,
      {
        shell: false,
        stdio: [
          "ignore",
          "pipe",
          "pipe",
        ],
        env:
          process.env,
      },
    );

  const entry:
    RuntimeEntry = {
      process:
        child,
      stopRequested:
        false,
      liveTimer:
        null,
    };

  runtimes.set(
    input.gameId,
    entry,
  );

  let stderrTail =
    "";

  child.stderr.on(
    "data",
    (
      chunk:
        Buffer,
    ) => {
      const text =
        chunk.toString(
          "utf8",
        );

      stderrTail =
        (
          stderrTail +
          text
        ).slice(
          -2000,
        );
    },
  );

  child.once(
    "error",
    (error) => {
      if (
        entry.liveTimer
      ) {
        clearTimeout(
          entry.liveTimer,
        );
      }

      runtimes.delete(
        input.gameId,
      );

      markEncoderError(
        input.gameId,
        sanitizedMessage(
          error,
        ),
      );
    },
  );

  child.once(
    "exit",
    (
      code,
      signal,
    ) => {
      if (
        entry.liveTimer
      ) {
        clearTimeout(
          entry.liveTimer,
        );
      }

      runtimes.delete(
        input.gameId,
      );

      if (
        entry.stopRequested
      ) {
        markEncoderStopped(
          input.gameId,
        );
        return;
      }

      const detail =
        stderrTail
          .trim()
          .split(
            "\n",
          )
          .slice(
            -2,
          )
          .join(
            " ",
          );

      markEncoderError(
        input.gameId,
        `FFmpeg exited unexpectedly (code=${String(
          code,
        )}, signal=${String(
          signal,
        )}).${
          detail
            ? ` ${detail}`
            : ""
        }`,
      );
    },
  );

  entry.liveTimer =
    setTimeout(
      () => {
        if (
          runtimes.get(
            input.gameId,
          ) ===
            entry &&
          child.exitCode ===
            null
        ) {
          markEncoderLive(
            input.gameId,
          );
        }
      },
      2000,
    );
}

export async function stopEncoderRuntime(
  gameId: string,
): Promise<void> {
  const entry =
    runtimes.get(
      gameId,
    );

  if (!entry) {
    markEncoderStopped(
      gameId,
    );
    return;
  }

  entry.stopRequested =
    true;

  if (
    entry.liveTimer
  ) {
    clearTimeout(
      entry.liveTimer,
    );

    entry.liveTimer =
      null;
  }

  entry.process.kill(
    "SIGTERM",
  );

  setTimeout(
    () => {
      const current =
        runtimes.get(
          gameId,
        );

      if (
        current ===
          entry &&
        entry.process.exitCode ===
          null
      ) {
        entry.process.kill(
          "SIGKILL",
        );
      }
    },
    5000,
  );
}

export function encoderRuntimeSnapshot(
  gameId: string,
): {
  runtimeActive: boolean;
  session:
    ReturnType<
      typeof getEncoderSession
    >;
} {
  return {
    runtimeActive:
      isEncoderRuntimeActive(
        gameId,
      ),
    session:
      getEncoderSession(
        gameId,
      ),
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

const runtimeImport =
  'import { encoderRuntimeSnapshot, startEncoderRuntime, stopEncoderRuntime } from "../services/encoderRuntime.js";';

if (
  !text.includes(
    runtimeImport,
  )
) {
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
        runtimeImport +
        "\n",
    );
}

/*
 * GET now includes runtimeActive but keeps the existing session response.
 */
const oldGet =
`      return {
        success: true,
        data: {
          session:
            getEncoderSession(
              gameId,
            ),
        },
      };`;

if (
  text.includes(
    oldGet,
  )
) {
  text =
    text.replace(
      oldGet,
`      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };`,
    );
}

/*
 * Replace the control-plane-only start result with actual runtime launch.
 */
const oldStart =
`      const session =
        beginEncoderStart(
          gameId,
        );

      return {
        success: true,
        data: {
          session,
          launchRequired:
            session.status ===
            "STARTING",
        },
      };`;

if (
  text.includes(
    oldStart,
  )
) {
  text =
    text.replace(
      oldStart,
`      beginEncoderStart(
        gameId,
      );

      try {
        await startEncoderRuntime({
          gameId,
          destination,
        });
      } catch (error) {
        const message =
          error instanceof Error
            ? error.message
            : "Unable to launch encoder runtime.";

        return reply.code(500).send({
          success: false,
          error:
            message,
        });
      }

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };`,
    );
}

/*
 * Replace the placeholder stop completion with runtime stop.
 */
const oldStop =
`      const current =
        beginEncoderStop(
          gameId,
        );

      /*
       * 20.4 does not launch a real encoder process yet.
       * If nothing is actually running, complete the control transition.
       */
      const session =
        current.status ===
          "STOPPING"
          ? markEncoderStopped(
              gameId,
            )
          : current;

      return {
        success: true,
        data: {
          session,
        },
      };`;

if (
  text.includes(
    oldStop,
  )
) {
  text =
    text.replace(
      oldStop,
`      beginEncoderStop(
        gameId,
      );

      await stopEncoderRuntime(
        gameId,
      );

      const snapshot =
        encoderRuntimeSnapshot(
          gameId,
        );

      return {
        success: true,
        data: {
          session:
            snapshot.session,
          runtimeActive:
            snapshot.runtimeActive,
        },
      };`,
    );
}

/*
 * Remove imports that are no longer used after the runtime wiring.
 */
text =
  text.replace(
    "  markEncoderStopped,\n",
    "",
  );

for (
  const required of
    [
      "startEncoderRuntime",
      "stopEncoderRuntime",
      "encoderRuntimeSnapshot",
      "runtimeActive",
    ]
) {
  if (
    !text.includes(
      required,
    )
  ) {
    throw new Error(
      `20.5 route verification failed: ${required}`,
    );
  }
}

fs.writeFileSync(
  file,
  text,
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 20.5 — Encoder runtime adapter and FFmpeg process control

SportsOS can now launch and stop a real FFmpeg child process for an armed encoder session.

Runtime properties:

- `spawn()` is used with `shell: false`
- the FFmpeg binary defaults to `ffmpeg`
- `SPORTSOS_FFMPEG_PATH` may override the binary path
- the source URL is supplied server-side by `SPORTSOS_ENCODER_SOURCE_URL` or `SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE`
- `{gameId}` may be used in the source template
- credentials are resolved server-side from `env://VARIABLE_NAME`
- resolved credential values are not returned by the API and are not logged by SportsOS
- stop sends `SIGTERM`, then `SIGKILL` after 5 seconds if required

Credential references supported by this milestone:

```text
env://MY_STREAM_KEY
```

The referenced environment variable must exist in the API container.

Output behavior:

- RTMP/RTMPS uses FLV output
- SRT uses MPEG-TS output
- audio/video streams are copied without transcoding in this first runtime adapter

Session transition:

```text
READY destination
      ↓
STARTING
      ↓
FFmpeg survives initial 2-second launch window
      ↓
LIVE
```

Unexpected FFmpeg exit moves the encoder session to `ERROR`.

This launch-health window confirms process survival only. Later milestones should add encoder telemetry and upstream publishing confirmation before treating `LIVE` as full end-to-end stream health.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.5 encoder runtime adapter / FFmpeg process control", () => {
  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const credentials =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamCredentialResolver.ts",
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

  it("launches FFmpeg without a shell", () => {
    expect(
      runtime,
    ).toContain(
      "spawn(",
    );

    expect(
      runtime,
    ).toContain(
      "shell: false",
    );

    expect(
      runtime,
    ).toContain(
      "SPORTSOS_FFMPEG_PATH",
    );
  });

  it("requires a server-side source URL", () => {
    expect(
      runtime,
    ).toContain(
      "SPORTSOS_ENCODER_SOURCE_URL",
    );

    expect(
      runtime,
    ).toContain(
      "SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE",
    );
  });

  it("resolves credentials only from environment references", () => {
    expect(
      credentials,
    ).toContain(
      '"env://"',
    );

    expect(
      credentials,
    ).toContain(
      "process.env",
    );

    expect(
      credentials,
    ).not.toContain(
      "console.log",
    );
  });

  it("supports RTMP FLV and SRT MPEG-TS outputs", () => {
    expect(
      runtime,
    ).toContain(
      '"flv"',
    );

    expect(
      runtime,
    ).toContain(
      '"mpegts"',
    );
  });

  it("promotes a surviving runtime to LIVE", () => {
    expect(
      runtime,
    ).toContain(
      "markEncoderLive",
    );

    expect(
      runtime,
    ).toContain(
      "2000",
    );
  });

  it("stops gracefully before forcing termination", () => {
    expect(
      runtime,
    ).toContain(
      '"SIGTERM"',
    );

    expect(
      runtime,
    ).toContain(
      '"SIGKILL"',
    );

    expect(
      runtime,
    ).toContain(
      "5000",
    );
  });

  it("wires start and stop API actions to the runtime adapter", () => {
    expect(
      route,
    ).toContain(
      "startEncoderRuntime",
    );

    expect(
      route,
    ).toContain(
      "stopEncoderRuntime",
    );

    expect(
      route,
    ).toContain(
      "runtimeActive",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 20.5 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - FFmpeg runtime adapter"
echo "  - shell-free process spawning"
echo "  - environment credential resolver"
echo "  - server-side encoder source URL"
echo "  - RTMP FLV output"
echo "  - SRT MPEG-TS output"
echo "  - process lifecycle -> encoder session state"
echo "  - graceful stop + forced fallback"
echo "  - runtimeActive API status"
echo "  - Milestone 20.5 regression tests"
echo
echo "Required runtime configuration before a real start:"
echo "  SPORTSOS_ENCODER_SOURCE_URL=<camera/input URL>"
echo "  or SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE=<URL containing {gameId}>"
echo "  credentialRef in SportsOS: env://YOUR_STREAM_SECRET"
echo "  API environment: YOUR_STREAM_SECRET=<actual secret>"
echo
echo "Optional:"
echo "  SPORTSOS_FFMPEG_PATH=/usr/bin/ffmpeg"
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
echo "  Milestone 20.6 - Encoder Telemetry / Publish Health"
