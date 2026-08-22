#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.9-fleet-update-orchestration-rollout-controls"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/app.ts" \
  "$ROOT/apps/api/src/routes/scoreboardFirmwareReleases.ts" \
  "$ROOT/apps/api/src/services/scoreboardFirmwareReleaseRegistry.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/firmware/page.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardFirmwareRollouts.ts"
ROUTE="apps/api/src/routes/scoreboardFirmwareRollouts.ts"
RELEASE_ROUTE="apps/api/src/routes/scoreboardFirmwareReleases.ts"
DASH="apps/dashboard/app/scoreboards/firmware/page.tsx"
TEST="packages/core/test/fleet-update-orchestration-rollout-controls-13.9.test.ts"

for file in "$SERVICE" "$ROUTE" "$RELEASE_ROUTE" "$DASH" "$TEST" "apps/api/src/app.ts"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$SERVICE")" \
  "$(dirname "$ROUTE")" \
  "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type FirmwareRolloutState =
  | "DRAFT"
  | "ACTIVE"
  | "PAUSED"
  | "COMPLETED"
  | "CANCELLED";

export type FirmwareRollout = {
  rolloutId: string;
  releaseId: string;
  state: FirmwareRolloutState;
  targetDeviceIds: string[];
  createdAt: string;
  updatedAt: string;
};

type RolloutStore = {
  version: 1;
  rollouts: FirmwareRollout[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-firmware-rollouts.json",
  );

let store =
  loadStore();

function loadStore(): RolloutStore {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as RolloutStore;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.rollouts,
      )
    ) {
      throw new Error(
        "Invalid firmware rollout store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      rollouts: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
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

export function createFirmwareRollout(input: {
  releaseId: string;
  targetDeviceIds: string[];
}): FirmwareRollout {
  const now =
    new Date().toISOString();

  const rollout: FirmwareRollout = {
    rolloutId:
      crypto.randomUUID(),
    releaseId:
      input.releaseId,
    state:
      "DRAFT",
    targetDeviceIds:
      [...new Set(
        input.targetDeviceIds,
      )],
    createdAt:
      now,
    updatedAt:
      now,
  };

  store.rollouts.push(
    rollout,
  );

  persistStore();

  return rollout;
}

export function listFirmwareRollouts(): FirmwareRollout[] {
  return [...store.rollouts]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}

export function getFirmwareRollout(
  rolloutId: string,
): FirmwareRollout | null {
  return (
    store.rollouts.find(
      (rollout) =>
        rollout.rolloutId ===
        rolloutId,
    ) ?? null
  );
}

export function updateFirmwareRolloutState(
  rolloutId: string,
  nextState: FirmwareRolloutState,
): FirmwareRollout | null {
  const rollout =
    getFirmwareRollout(
      rolloutId,
    );

  if (!rollout) {
    return null;
  }

  rollout.state =
    nextState;

  rollout.updatedAt =
    new Date().toISOString();

  persistStore();

  return rollout;
}

export function findActiveRolloutForDevice(
  deviceId: string,
): FirmwareRollout | null {
  return (
    store.rollouts.find(
      (rollout) =>
        rollout.state ===
          "ACTIVE" &&
        rollout.targetDeviceIds.includes(
          deviceId,
        ),
    ) ?? null
  );
}
EOF

cat > "$ROUTE" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

import {
  createFirmwareRollout,
  getFirmwareRollout,
  listFirmwareRollouts,
  updateFirmwareRolloutState,
  type FirmwareRolloutState,
} from "../services/scoreboardFirmwareRollouts.js";

import {
  getFirmwareRelease,
} from "../services/scoreboardFirmwareReleaseRegistry.js";

import {
  isVerifiedDevice,
} from "../services/scoreboardDeviceEnrollment.js";

const allowedTransitions: Record<
  FirmwareRolloutState,
  FirmwareRolloutState[]
> = {
  DRAFT: [
    "ACTIVE",
    "CANCELLED",
  ],
  ACTIVE: [
    "PAUSED",
    "COMPLETED",
    "CANCELLED",
  ],
  PAUSED: [
    "ACTIVE",
    "CANCELLED",
  ],
  COMPLETED: [],
  CANCELLED: [],
};

export async function registerScoreboardFirmwareRolloutRoutes(
  app: FastifyInstance,
) {
  app.get(
    "/scoreboard-firmware/rollouts",
    async () => ({
      success: true,
      data: {
        rollouts:
          listFirmwareRollouts(),
      },
    }),
  );

  app.get(
    "/scoreboard-firmware/rollouts/:rolloutId",
    async (request, reply) => {
      const { rolloutId } =
        request.params as {
          rolloutId: string;
        };

      const rollout =
        getFirmwareRollout(
          rolloutId,
        );

      if (!rollout) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware rollout not found.",
        });
      }

      return {
        success: true,
        data:
          rollout,
      };
    },
  );

  app.post(
    "/scoreboard-firmware/rollouts",
    async (request, reply) => {
      const body =
        request.body as {
          releaseId?: string;
          targetDeviceIds?: string[];
        };

      if (
        !body?.releaseId ||
        !Array.isArray(
          body.targetDeviceIds,
        ) ||
        body.targetDeviceIds.length === 0
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "releaseId and targetDeviceIds are required.",
        });
      }

      const release =
        getFirmwareRelease(
          body.releaseId,
        );

      if (!release) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware release not found.",
        });
      }

      const unverified =
        body.targetDeviceIds.filter(
          (deviceId) =>
            !isVerifiedDevice(
              deviceId,
            ),
        );

      if (
        unverified.length > 0
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "All rollout targets must be verified scoreboard devices.",
          data: {
            unverified,
          },
        });
      }

      const rollout =
        createFirmwareRollout({
          releaseId:
            body.releaseId,
          targetDeviceIds:
            body.targetDeviceIds,
        });

      return reply.code(201).send({
        success: true,
        data:
          rollout,
      });
    },
  );

  app.post(
    "/scoreboard-firmware/rollouts/:rolloutId/state",
    async (request, reply) => {
      const { rolloutId } =
        request.params as {
          rolloutId: string;
        };

      const body =
        request.body as {
          state?: FirmwareRolloutState;
        };

      const rollout =
        getFirmwareRollout(
          rolloutId,
        );

      if (!rollout) {
        return reply.code(404).send({
          success: false,
          error:
            "Firmware rollout not found.",
        });
      }

      if (
        !body?.state ||
        !allowedTransitions[
          rollout.state
        ].includes(
          body.state,
        )
      ) {
        return reply.code(409).send({
          success: false,
          error:
            `Invalid rollout transition from ${rollout.state}.`,
        });
      }

      return {
        success: true,
        data:
          updateFirmwareRolloutState(
            rolloutId,
            body.state,
          ),
      };
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const appFile =
  "apps/api/src/app.ts";

let app =
  fs.readFileSync(
    appFile,
    "utf8",
  );

const importLine =
  'import { registerScoreboardFirmwareRolloutRoutes } from "./routes/scoreboardFirmwareRollouts.js";';

if (!app.includes(importLine)) {
  const imports =
    app.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate API import block.",
    );
  }

  app =
    app.replace(
      imports[0],
      imports[0] +
        importLine +
        "\n",
    );
}

if (
  !app.includes(
    "await registerScoreboardFirmwareRolloutRoutes(app);",
  )
) {
  const anchors = [
    "await registerScoreboardFirmwareDeploymentStatusRoutes(app);",
    "await registerScoreboardFirmwareArtifactRoutes(app);",
    "return app;",
  ];

  let patched = false;

  for (const anchor of anchors) {
    if (!app.includes(anchor)) {
      continue;
    }

    if (anchor === "return app;") {
      app =
        app.replace(
          anchor,
          "await registerScoreboardFirmwareRolloutRoutes(app);\n\n  " +
            anchor,
        );
    } else {
      app =
        app.replace(
          anchor,
          anchor +
            "\n  await registerScoreboardFirmwareRolloutRoutes(app);",
        );
    }

    patched = true;
    break;
  }

  if (!patched) {
    throw new Error(
      "Unable to locate rollout route registration anchor.",
    );
  }
}

fs.writeFileSync(
  appFile,
  app,
);
NODE

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardFirmwareReleases.ts";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !text.includes(
    "findActiveRolloutForDevice",
  )
) {
  const importLine =
    'import { findActiveRolloutForDevice } from "../services/scoreboardFirmwareRollouts.js";';

  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate firmware release route imports.",
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

const offerRouteStart =
  text.indexOf(
    '"/scoreboard-firmware/device-offer"',
  );

if (offerRouteStart === -1) {
  throw new Error(
    "Unable to locate device-offer route.",
  );
}

if (
  !text.includes(
    "const rollout =\n        findActiveRolloutForDevice(",
  )
) {
  const verificationAnchor =
`      if (
        !isVerifiedDevice(
          query.deviceId,
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Verified scoreboard device required.",
        });
      }`;

  if (!text.includes(verificationAnchor)) {
    throw new Error(
      "Unable to locate verified-device gate in device-offer route.",
    );
  }

  const rolloutGate =
`${verificationAnchor}

      const rollout =
        findActiveRolloutForDevice(
          query.deviceId,
        );

      if (!rollout) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: null,
          },
        };
      }`;

  text =
    text.replace(
      verificationAnchor,
      rolloutGate,
    );
}

if (
  !text.includes(
    "releaseId: rollout.releaseId",
  )
) {
  const latestAnchor =
`      const release =
        getLatestCompatibleFirmwareRelease({
          currentVersion:
            query.currentVersion,
          channel:
            query.channel ??
            "stable",
          target:
            query.target ??
            "esp32dev",
        });`;

  if (!text.includes(latestAnchor)) {
    throw new Error(
      "Unable to locate latest-compatible release selection.",
    );
  }

  const replacement =
`      const release =
        getFirmwareRelease(
          rollout.releaseId,
        );

      if (
        release &&
        (
          release.channel !==
            (query.channel ?? "stable") ||
          release.target !==
            (query.target ?? "esp32dev")
        )
      ) {
        return {
          success: true,
          data: {
            updateAvailable: false,
            offer: null,
            rollout: {
              rolloutId:
                rollout.rolloutId,
              state:
                rollout.state,
            },
          },
        };
      }`;

  text =
    text.replace(
      latestAnchor,
      replacement,
    );
}

if (
  !text.includes(
    "rolloutId:\n              rollout.rolloutId",
  )
) {
  text =
    text.replace(
`          offer: {
            deviceId:
              query.deviceId,`,
`          rollout: {
            rolloutId:
              rollout.rolloutId,
            state:
              rollout.state,
          },
          offer: {
            deviceId:
              query.deviceId,`,
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
  "apps/dashboard/app/scoreboards/firmware/page.tsx";

let text =
  fs.readFileSync(
    file,
    "utf8",
  );

if (!text.includes("type FirmwareRollout")) {
  const anchor =
    "type DeploymentReport = {";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate DeploymentReport type.",
    );
  }

  const typeBlock = `type FirmwareRollout = {
  rolloutId: string;
  releaseId: string;
  state:
    | "DRAFT"
    | "ACTIVE"
    | "PAUSED"
    | "COMPLETED"
    | "CANCELLED";
  targetDeviceIds: string[];
  createdAt: string;
  updatedAt: string;
};

`;

  text =
    text.slice(0, idx) +
    typeBlock +
    text.slice(idx);
}

if (
  !text.includes(
    "const [rollouts",
  )
) {
  const anchor =
`  const [
    loading,
    setLoading,
  ] = useState(true);`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate firmware dashboard loading state.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

  const [
    rollouts,
    setRollouts,
  ] = useState<FirmwareRollout[]>([]);

  const [
    selectedReleaseId,
    setSelectedReleaseId,
  ] = useState("");

  const [
    targetDevices,
    setTargetDevices,
  ] = useState("");

  const [
    rolloutMessage,
    setRolloutMessage,
  ] = useState("");`,
    );
}

if (
  !text.includes(
    "/scoreboard-firmware/rollouts",
  )
) {
  text =
    text.replace(
`          fetch(
            \`${API_BASE}/scoreboard-firmware/deployments\`,
            {
              cache: "no-store",
            },
          ),`,
`          fetch(
            \`${API_BASE}/scoreboard-firmware/deployments\`,
            {
              cache: "no-store",
            },
          ),
          fetch(
            \`${API_BASE}/scoreboard-firmware/rollouts\`,
            {
              cache: "no-store",
            },
          ),`,
    );

  text =
    text.replace(
`        const [
          releaseJson,
          reportJson,
        ] = await Promise.all([
          releaseResponse.json(),
          reportResponse.json(),
        ]);`,
`        const [
          releaseJson,
          reportJson,
          rolloutJson,
        ] = await Promise.all([
          releaseResponse.json(),
          reportResponse.json(),
          rolloutResponse.json(),
        ]);`,
    );

  text =
    text.replace(
`        const [
          releaseResponse,
          reportResponse,
        ] = await Promise.all([`,
`        const [
          releaseResponse,
          reportResponse,
          rolloutResponse,
        ] = await Promise.all([`,
    );

  text =
    text.replace(
`          setReports(
            reportJson?.data?.reports ?? [],
          );`,
`          setReports(
            reportJson?.data?.reports ?? [],
          );

          setRollouts(
            rolloutJson?.data?.rollouts ?? [],
          );`,
    );
}

if (
  !text.includes(
    "async function createRollout",
  )
) {
  const anchor =
    "  return (";

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate firmware dashboard return.",
    );
  }

  const handlers = `  async function createRollout() {
    const targetDeviceIds =
      targetDevices
        .split(",")
        .map((value) =>
          value.trim(),
        )
        .filter(Boolean);

    if (
      !selectedReleaseId ||
      targetDeviceIds.length === 0
    ) {
      setRolloutMessage(
        "Select a release and enter at least one verified device ID.",
      );
      return;
    }

    const response =
      await fetch(
        \`${API_BASE}/scoreboard-firmware/rollouts\`,
        {
          method: "POST",
          headers: {
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            releaseId:
              selectedReleaseId,
            targetDeviceIds,
          }),
        },
      );

    const json =
      await response.json();

    if (
      !response.ok ||
      !json?.success
    ) {
      setRolloutMessage(
        json?.error ??
          "Unable to create rollout.",
      );
      return;
    }

    setRolloutMessage(
      "Rollout created in DRAFT state.",
    );

    setRollouts((current) => [
      json.data,
      ...current,
    ]);
  }

  async function transitionRollout(
    rolloutId: string,
    state: FirmwareRollout["state"],
  ) {
    const response =
      await fetch(
        \`${API_BASE}/scoreboard-firmware/rollouts/\${encodeURIComponent(
          rolloutId,
        )}/state\`,
        {
          method: "POST",
          headers: {
            "Content-Type":
              "application/json",
          },
          body: JSON.stringify({
            state,
          }),
        },
      );

    const json =
      await response.json();

    if (
      !response.ok ||
      !json?.success
    ) {
      setRolloutMessage(
        json?.error ??
          "Unable to update rollout.",
      );
      return;
    }

    setRollouts((current) =>
      current.map((rollout) =>
        rollout.rolloutId ===
        rolloutId
          ? json.data
          : rollout,
      ),
    );
  }

`;

  text =
    text.slice(0, idx) +
    handlers +
    text.slice(idx);
}

if (
  !text.includes(
    "Fleet Rollouts",
  )
) {
  const anchor =
    '<section className="mb-8 rounded-xl border border-slate-800 p-5">';

  const idx =
    text.indexOf(anchor);

  if (idx === -1) {
    throw new Error(
      "Unable to locate first firmware dashboard section.",
    );
  }

  const section = `<section className="mb-8 rounded-xl border border-slate-800 p-5">
        <h2 className="text-xl font-semibold">
          Fleet Rollouts
        </h2>

        <div className="mt-4 grid gap-3 md:grid-cols-3">
          <select
            value={selectedReleaseId}
            onChange={(event) =>
              setSelectedReleaseId(
                event.target.value,
              )
            }
            className="rounded-lg border border-slate-700 bg-transparent px-3 py-2"
          >
            <option value="">
              Select release
            </option>
            {releases.map((release) => (
              <option
                key={release.releaseId}
                value={release.releaseId}
              >
                {release.version} · {release.channel}
              </option>
            ))}
          </select>

          <input
            value={targetDevices}
            onChange={(event) =>
              setTargetDevices(
                event.target.value,
              )
            }
            placeholder="device-1, device-2"
            className="rounded-lg border border-slate-700 bg-transparent px-3 py-2"
          />

          <button
            type="button"
            onClick={() =>
              void createRollout()
            }
            className="rounded-lg border border-slate-700 px-4 py-2"
          >
            Create Draft Rollout
          </button>
        </div>

        {rolloutMessage && (
          <p className="mt-3 text-sm text-slate-400">
            {rolloutMessage}
          </p>
        )}

        <div className="mt-5 space-y-3">
          {rollouts.length === 0 ? (
            <p className="text-sm text-slate-500">
              No firmware rollouts yet.
            </p>
          ) : (
            rollouts.map((rollout) => (
              <div
                key={rollout.rolloutId}
                className="rounded-lg border border-slate-800 p-4"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="font-medium">
                      {rollout.releaseId}
                    </div>
                    <div className="mt-1 text-sm text-slate-400">
                      {rollout.state} · {rollout.targetDeviceIds.length} device(s)
                    </div>
                  </div>

                  <div className="flex flex-wrap gap-2">
                    {rollout.state === "DRAFT" && (
                      <button
                        type="button"
                        onClick={() =>
                          void transitionRollout(
                            rollout.rolloutId,
                            "ACTIVE",
                          )
                        }
                        className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
                      >
                        Start
                      </button>
                    )}

                    {rollout.state === "ACTIVE" && (
                      <>
                        <button
                          type="button"
                          onClick={() =>
                            void transitionRollout(
                              rollout.rolloutId,
                              "PAUSED",
                            )
                          }
                          className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
                        >
                          Pause
                        </button>

                        <button
                          type="button"
                          onClick={() =>
                            void transitionRollout(
                              rollout.rolloutId,
                              "COMPLETED",
                            )
                          }
                          className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
                        >
                          Complete
                        </button>
                      </>
                    )}

                    {rollout.state === "PAUSED" && (
                      <button
                        type="button"
                        onClick={() =>
                          void transitionRollout(
                            rollout.rolloutId,
                            "ACTIVE",
                          )
                        }
                        className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
                      >
                        Resume
                      </button>
                    )}

                    {[
                      "DRAFT",
                      "ACTIVE",
                      "PAUSED",
                    ].includes(
                      rollout.state,
                    ) && (
                      <button
                        type="button"
                        onClick={() =>
                          void transitionRollout(
                            rollout.rolloutId,
                            "CANCELLED",
                          )
                        }
                        className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
                      >
                        Cancel
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

`;

  text =
    text.slice(0, idx) +
    section +
    text.slice(idx);
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

describe("Milestone 13.9 fleet rollout controls", () => {
  it("persists rollout plans", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareRollouts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-firmware-rollouts.json",
    );

    expect(service).toContain(
      "createFirmwareRollout",
    );
  });

  it("supports draft active paused completed cancelled states", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardFirmwareRollouts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "DRAFT",
      "ACTIVE",
      "PAUSED",
      "COMPLETED",
      "CANCELLED",
    ]) {
      expect(service).toContain(state);
    }
  });

  it("requires verified rollout targets", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareRollouts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "isVerifiedDevice",
    );

    expect(routes).toContain(
      "All rollout targets must be verified scoreboard devices.",
    );
  });

  it("adds rollout state transition controls", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareRollouts.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-firmware/rollouts/:rolloutId/state",
    );

    expect(routes).toContain(
      "allowedTransitions",
    );
  });

  it("gates device OTA offers behind active rollout targeting", () => {
    const releases = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardFirmwareReleases.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(releases).toContain(
      "findActiveRolloutForDevice",
    );

    expect(releases).toContain(
      "rollout.releaseId",
    );
  });

  it("adds fleet rollout controls to dashboard", () => {
    const dashboard = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/firmware/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(dashboard).toContain(
      "Fleet Rollouts",
    );

    expect(dashboard).toContain(
      "Create Draft Rollout",
    );

    expect(dashboard).toContain(
      "Pause",
    );

    expect(dashboard).toContain(
      "Resume",
    );

    expect(dashboard).toContain(
      "Cancel",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent firmware rollout plans"
echo "  - DRAFT / ACTIVE / PAUSED / COMPLETED / CANCELLED states"
echo "  - verified-device targeting requirement"
echo "  - rollout start / pause / resume / complete / cancel APIs"
echo "  - device OTA offers gated by ACTIVE rollout membership"
echo "  - firmware fleet rollout controls"
echo "  - Milestone 13.9 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild:"
echo "  docker compose up -d --build api dashboard"
echo
echo "Next after green:"
echo "  Milestone 13.10 - Firmware Fleet Acceptance / Closeout"
