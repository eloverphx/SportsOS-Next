#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-15.9-ui-recovery-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/services/scoreboardControlIncidentResolution.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

PANEL="apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx"
TEST="packages/core/test/incident-resolution-ui-recovery-15.9.test.ts"

for file in "$PANEL" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("type IncidentResolution")) {
  const marker =
    "type PhysicalControlIncident";

  const idx =
    text.indexOf(marker);

  if (idx === -1) {
    throw new Error(
      "Unable to locate PhysicalControlIncident type.",
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

if (!text.includes("incidentResolutions")) {
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

if (
  !text.includes(
    "/scoreboard-control-incident-resolutions",
  )
) {
  const promiseStart =
    text.indexOf(
      "await Promise.all([",
    );

  if (promiseStart === -1) {
    throw new Error(
      "Unable to locate load Promise.all().",
    );
  }

  const healthFetch =
`        fetch(
          \`\${API_BASE}/scoreboard-control-incidents?limit=50\`,
          { cache: "no-store" },
        ),`;

  if (!text.includes(healthFetch)) {
    throw new Error(
      "Unable to locate incident fetch.",
    );
  }

  text =
    text.replace(
      healthFetch,
`${healthFetch}
        fetch(
          \`\${API_BASE}/scoreboard-control-incident-resolutions\`,
          { cache: "no-store" },
        ),`
    );

  const destructureMarker =
    "        incidentsResponse,\n";

  if (!text.includes(destructureMarker)) {
    throw new Error(
      "Unable to locate incidentsResponse destructure.",
    );
  }

  text =
    text.replace(
      destructureMarker,
      destructureMarker +
        "        incidentResolutionResponse,\n",
    );

  const incidentBlock =
`      if (incidentsResponse.ok) {
        const incidentsJson =
          await incidentsResponse.json();

        setControlIncidents(
          incidentsJson?.data?.incidents ??
          [],
        );
      }`;

  if (!text.includes(incidentBlock)) {
    throw new Error(
      "Unable to locate incidents response block.",
    );
  }

  text =
    text.replace(
      incidentBlock,
`${incidentBlock}

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

if (!text.includes("updateIncidentResolution")) {
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
            body:
              JSON.stringify({
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
  const mapOpen =
`            {controlIncidents.map(
              (incident) => (`;

  if (!text.includes(mapOpen)) {
    throw new Error(
      "Unable to locate incident timeline map.",
    );
  }

  text =
    text.replace(
      mapOpen,
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

  const searchStart =
    text.indexOf(
      "resolutionForIncident",
    );

  const closeMarker =
`                </div>
              ),
            )}`;

  const closeIndex =
    text.indexOf(
      closeMarker,
      searchStart,
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

describe("Milestone 15.9 incident-resolution UI recovery", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores incident-resolution type and state", () => {
    expect(panel).toContain(
      "type IncidentResolution",
    );

    expect(panel).toContain(
      "incidentResolutions",
    );

    expect(panel).toContain(
      "incidentNotes",
    );
  });

  it("loads incident-resolution inventory", () => {
    expect(panel).toContain(
      "/scoreboard-control-incident-resolutions",
    );
  });

  it("restores acknowledge and resolve actions", () => {
    expect(panel).toContain(
      "updateIncidentResolution",
    );

    expect(panel).toContain(
      "Acknowledge",
    );

    expect(panel).toContain(
      "Resolve",
    );
  });

  it("shows latest incident resolution state", () => {
    expect(panel).toContain(
      "resolutionForIncident",
    );

    expect(panel).toContain(
      "Latest note:",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.9 UI recovery installed"
echo "============================================================"
echo
echo "Restored:"
echo "  - IncidentResolution type"
echo "  - incident resolution state"
echo "  - resolution inventory fetch"
echo "  - acknowledge action"
echo "  - resolve action"
echo "  - resolution notes/status display"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry 15.10:"
echo "  bash sportsos-milestone-15.10-game-day-control-safety-acceptance-closeout.sh"
