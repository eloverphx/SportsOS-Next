#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.9-incident-ack-resolution-workflow-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardControlAudit.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/services/scoreboardControlAuthorization.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

SERVICE="apps/api/src/services/scoreboardControlIncidentResolution.ts"
ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/incident-ack-resolution-workflow-15.9.test.ts"

for file in "$SERVICE" "$ROUTE" "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type ScoreboardControlIncidentStatus =
  | "OPEN"
  | "ACKNOWLEDGED"
  | "RESOLVED";

export type ScoreboardControlIncidentResolution = {
  auditId: string;
  status: ScoreboardControlIncidentStatus;
  note: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  updatedAt: string;
};

type Store = {
  version: 1;
  resolutions:
    ScoreboardControlIncidentResolution[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-control-incident-resolution.json",
  );

let store = load();

function load(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.resolutions,
      )
    ) {
      throw new Error(
        "Invalid incident-resolution store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      resolutions: [],
    };
  }
}

function persist(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
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

export function getScoreboardControlIncidentResolution(
  auditId: string,
): ScoreboardControlIncidentResolution | null {
  return (
    store.resolutions.find(
      (item) =>
        item.auditId === auditId,
    ) ?? null
  );
}

export function setScoreboardControlIncidentResolution(input: {
  auditId: string;
  status:
    ScoreboardControlIncidentStatus;
  note?: string | null;
  actorUserId: string | null;
  actorRoles: string[];
}): ScoreboardControlIncidentResolution {
  const record:
    ScoreboardControlIncidentResolution = {
      auditId:
        input.auditId,
      status:
        input.status,
      note:
        input.note?.trim() ||
        null,
      actorUserId:
        input.actorUserId,
      actorRoles:
        [...input.actorRoles],
      updatedAt:
        new Date().toISOString(),
    };

  store.resolutions =
    store.resolutions.filter(
      (item) =>
        item.auditId !==
        input.auditId,
    );

  store.resolutions.push(
    record,
  );

  persist();

  return record;
}

export function listScoreboardControlIncidentResolutions():
  ScoreboardControlIncidentResolution[] {
  return [...store.resolutions]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}
EOF

node <<'NODE'
const fs = require("fs");
const file =
  "apps/api/src/routes/scoreboardControlPolicy.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { getScoreboardControlIncidentResolution, listScoreboardControlIncidentResolutions, setScoreboardControlIncidentResolution } from "../services/scoreboardControlIncidentResolution.js";';

if (!text.includes(importLine)) {
  const imports =
    text.match(/^(import[\s\S]*?;\n)+/);

  if (!imports) {
    throw new Error(
      "Unable to locate control-policy imports.",
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

if (!text.includes("/scoreboard-control-incidents/:auditId")) {
  const marker =
    "export async function registerScoreboardControlPolicyRoutes";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate control-policy route registration.",
    );
  }

  const open =
    text.indexOf(
      "{",
      idx,
    );

  if (open === -1) {
    throw new Error(
      "Unable to locate route registration body.",
    );
  }

  const routes = `
  app.get(
    "/scoreboard-control-incident-resolutions",
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
          resolutions:
            listScoreboardControlIncidentResolutions(),
        },
      };
    },
  );

  app.put(
    "/scoreboard-control-incidents/:auditId",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error:
            "Physical control policy write permission required.",
        });
      }

      const params =
        request.params as {
          auditId?: string;
        };

      const body =
        request.body as {
          status?:
            | "OPEN"
            | "ACKNOWLEDGED"
            | "RESOLVED";
          note?: string | null;
        };

      const auditId =
        params.auditId?.trim();

      if (!auditId) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident audit ID is required.",
        });
      }

      if (
        body.status !== "OPEN" &&
        body.status !== "ACKNOWLEDGED" &&
        body.status !== "RESOLVED"
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "Incident status must be OPEN, ACKNOWLEDGED, or RESOLVED.",
        });
      }

      if (
        body.status === "RESOLVED" &&
        !body.note?.trim()
      ) {
        return reply.code(400).send({
          success: false,
          error:
            "A resolution note is required when resolving an incident.",
        });
      }

      const principal =
        getScoreboardControlPrincipal(
          request,
        );

      const previous =
        getScoreboardControlIncidentResolution(
          auditId,
        );

      const resolution =
        setScoreboardControlIncidentResolution({
          auditId,
          status:
            body.status,
          note:
            body.note,
          actorUserId:
            principal.userId,
          actorRoles:
            principal.roles,
        });

      return {
        success: true,
        data: {
          previous,
          resolution,
        },
      };
    },
  );

`;

  text =
    text.slice(0, open + 1) +
    routes +
    text.slice(open + 1);
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("type IncidentResolution")) {
  const marker =
    "type PhysicalControlIncident";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate incident type.",
    );
  }

  text =
    text.slice(0, idx) +
`type IncidentResolution = {
  auditId: string;
  status:
    | "OPEN"
    | "ACKNOWLEDGED"
    | "RESOLVED";
  note: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  updatedAt: string;
};

` +
    text.slice(idx);
}

if (!text.includes("const [incidentResolutions")) {
  const marker =
    "const [controlIncidents, setControlIncidents]";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate incident state.",
    );
  }

  text =
    text.slice(0, idx) +
`const [incidentResolutions, setIncidentResolutions] =
    useState<IncidentResolution[]>([]);

  const [incidentNotes, setIncidentNotes] =
    useState<Record<string, string>>({});

  ` +
    text.slice(idx);
}

if (!text.includes("/scoreboard-control-incident-resolutions")) {
  text =
    text.replace(
`        fetch(
          \`\${API_BASE}/scoreboard-control-incidents?limit=50\`,
          { cache: "no-store" },
        ),
      ]);`,
`        fetch(
          \`\${API_BASE}/scoreboard-control-incidents?limit=50\`,
          { cache: "no-store" },
        ),
        fetch(
          \`\${API_BASE}/scoreboard-control-incident-resolutions\`,
          { cache: "no-store" },
        ),
      ]);`
    );

  text =
    text.replace(
`        incidentsResponse,
      ] = await Promise.all([`,
`        incidentsResponse,
        incidentResolutionResponse,
      ] = await Promise.all([`
    );

  const anchor =
`      if (incidentsResponse.ok) {
        const incidentsJson =
          await incidentsResponse.json();

        setControlIncidents(
          incidentsJson?.data?.incidents ??
          [],
        );
      }`;

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate incident response block.",
    );
  }

  text =
    text.replace(
      anchor,
`${anchor}

      if (incidentResolutionResponse.ok) {
        const resolutionJson =
          await incidentResolutionResponse.json();

        setIncidentResolutions(
          resolutionJson?.data?.resolutions ??
          [],
        );
      }`
    );
}

if (!text.includes("async function updateIncidentResolution")) {
  const marker =
    "  async function updateEmergencyLock";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate operator action insertion point.",
    );
  }

  text =
    text.slice(0, idx) +
`  async function updateIncidentResolution(
    auditId: string,
    status:
      | "ACKNOWLEDGED"
      | "RESOLVED",
  ) {
    const note =
      incidentNotes[auditId]?.trim() ||
      "";

    if (
      status === "RESOLVED" &&
      !note
    ) {
      setError(
        "Enter a resolution note before resolving the incident.",
      );
      return;
    }

    setSaving(true);

    try {
      const response =
        await fetch(
          \`\${API_BASE}/scoreboard-control-incidents/\${encodeURIComponent(auditId)}\`,
          {
            method: "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body: JSON.stringify({
              status,
              note:
                note ||
                null,
            }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          \`Incident update failed (\${response.status}).\`,
        );
      }

      setIncidentNotes(
        (current) => ({
          ...current,
          [auditId]: "",
        }),
      );

      setError(null);
      await loadPolicies();
    } catch (incidentError) {
      setError(
        incidentError instanceof Error
          ? incidentError.message
          : "Unable to update physical-control incident.",
      );
    } finally {
      setSaving(false);
    }
  }

` +
    text.slice(idx);
}

if (!text.includes("resolutionForIncident")) {
  const mapMarker =
`            {controlIncidents.map(
              (incident) => (`;

  if (!text.includes(mapMarker)) {
    throw new Error(
      "Unable to locate incident timeline map.",
    );
  }

  text =
    text.replace(
      mapMarker,
`            {controlIncidents.map(
              (incident) => {
                const resolutionForIncident =
                  incidentResolutions.find(
                    (item) =>
                      item.auditId ===
                      incident.auditId,
                  );

                return (`
    );

  const closeMarker =
`                </div>
              ),
            )}`;

  const closeIndex =
    text.indexOf(
      closeMarker,
      text.indexOf(
        "resolutionForIncident",
      ),
    );

  if (closeIndex === -1) {
    throw new Error(
      "Unable to locate incident map close.",
    );
  }

  const actionBlock =
`                  <div className="mt-3 border-t border-slate-800 pt-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-xs font-medium text-slate-400">
                        Status:{" "}
                        {resolutionForIncident?.status ?? "OPEN"}
                      </span>

                      {resolutionForIncident?.updatedAt && (
                        <span className="text-xs text-slate-500">
                          Updated {resolutionForIncident.updatedAt}
                        </span>
                      )}
                    </div>

                    <input
                      value={
                        incidentNotes[incident.auditId] ??
                        ""
                      }
                      onChange={(event) =>
                        setIncidentNotes(
                          (current) => ({
                            ...current,
                            [incident.auditId]:
                              event.target.value,
                          }),
                        )
                      }
                      placeholder="Acknowledgement or resolution note"
                      className="mt-2 w-full rounded border border-slate-800 bg-slate-950 px-3 py-2 text-xs"
                    />

                    <div className="mt-2 flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() =>
                          void updateIncidentResolution(
                            incident.auditId,
                            "ACKNOWLEDGED",
                          )
                        }
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Acknowledge
                      </button>

                      <button
                        type="button"
                        disabled={saving}
                        onClick={() =>
                          void updateIncidentResolution(
                            incident.auditId,
                            "RESOLVED",
                          )
                        }
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Resolve
                      </button>
                    </div>

                    {resolutionForIncident?.note && (
                      <p className="mt-2 text-xs text-slate-400">
                        Latest note: {resolutionForIncident.note}
                      </p>
                    )}
                  </div>
`;

  text =
    text.slice(0, closeIndex) +
    actionBlock +
    text.slice(closeIndex);

  text =
    text.replace(
      closeMarker,
`                </div>
                );
              },
            )}`
    );
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

describe("Milestone 15.9 incident acknowledgement / resolution workflow", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlIncidentResolution.ts",
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

  it("persists open acknowledged and resolved states", () => {
    expect(service).toContain('"OPEN"');
    expect(service).toContain('"ACKNOWLEDGED"');
    expect(service).toContain('"RESOLVED"');
    expect(service).toContain(
      "scoreboard-control-incident-resolution.json",
    );
  });

  it("attributes incident updates to authenticated actors", () => {
    expect(service).toContain("actorUserId");
    expect(service).toContain("actorRoles");
    expect(route).toContain(
      "getScoreboardControlPrincipal",
    );
  });

  it("requires elevated policy write permission for incident updates", () => {
    expect(route).toContain(
      "/scoreboard-control-incidents/:auditId",
    );
    expect(route).toContain(
      '"CONTROL_POLICY_WRITE"',
    );
  });

  it("requires a note when resolving an incident", () => {
    expect(route).toContain(
      "A resolution note is required when resolving an incident.",
    );
  });

  it("adds acknowledge and resolve controls to the incident timeline", () => {
    expect(panel).toContain("Acknowledge");
    expect(panel).toContain("Resolve");
    expect(panel).toContain(
      "updateIncidentResolution",
    );
    expect(panel).toContain(
      "resolutionForIncident",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - persistent incident-resolution registry"
echo "  - OPEN / ACKNOWLEDGED / RESOLVED states"
echo "  - actor user/role attribution"
echo "  - required resolution notes"
echo "  - permission-protected incident update API"
echo "  - GET incident-resolution inventory"
echo "  - operator Acknowledge / Resolve controls"
echo "  - latest resolution status/note display"
echo "  - Milestone 15.9 regression tests"
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
echo "  Milestone 15.10 - Game-Day Control Safety Acceptance / Closeout"
