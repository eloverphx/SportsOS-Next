#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-23.8-operator-notes-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

SERVICE="apps/api/src/services/broadcastOperatorNotes.ts"
ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
FOCUS="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx"
TEST="packages/core/test/broadcast-operator-notes-23.8.test.ts"
DOC="docs/BROADCAST-OPERATIONS-CONSOLE.md"

for required in \
  ".git" \
  "$ROUTE" \
  "$FOCUS" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$SERVICE" "$ROUTE" "$FOCUS" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type BroadcastOperatorNote = {
  id: string;
  gameId: string;
  operator: string;
  note: string;
  createdAt: string;
};

type Store = {
  version: 1;
  notes: BroadcastOperatorNote[];
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
    "broadcast-operator-notes.json",
  );

let store =
  loadStore();

function loadStore(): Store {
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
        parsed.notes,
      )
    ) {
      throw new Error(
        "Invalid broadcast operator notes store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      notes: [],
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

export function listBroadcastOperatorNotes(
  gameId: string,
  limit = 50,
): BroadcastOperatorNote[] {
  const safeLimit =
    Math.max(
      1,
      Math.min(
        Math.floor(
          limit,
        ),
        200,
      ),
    );

  return store.notes
    .filter(
      (note) =>
        note.gameId ===
        gameId,
    )
    .slice(
      -safeLimit,
    )
    .reverse()
    .map(
      (note) => ({
        ...note,
      }),
    );
}

export function addBroadcastOperatorNote(input: {
  gameId: string;
  operator: string;
  note: string;
}): BroadcastOperatorNote {
  const operator =
    input.operator.trim();

  const note =
    input.note.trim();

  if (!operator) {
    throw new Error(
      "Operator name is required.",
    );
  }

  if (!note) {
    throw new Error(
      "Operator note is required.",
    );
  }

  const item: BroadcastOperatorNote = {
    id:
      `broadcast-note-${input.gameId}-${Date.now()}-${Math.random()
        .toString(36)
        .slice(2, 8)}`,
    gameId:
      input.gameId,
    operator,
    note,
    createdAt:
      new Date().toISOString(),
  };

  store.notes.push(
    item,
  );

  if (
    store.notes.length >
    2500
  ) {
    store.notes =
      store.notes.slice(
        -2500,
      );
  }

  persistStore();

  return {
    ...item,
  };
}
EOF

node <<'NODE'
const fs=require("fs");
const f="apps/api/src/routes/broadcastSessionCoordinator.ts";
let s=fs.readFileSync(f,"utf8");

const importLine=`import {
  addBroadcastOperatorNote,
  listBroadcastOperatorNotes,
} from "../services/broadcastOperatorNotes.js";`;

if(!s.includes("listBroadcastOperatorNotes")) {
  const imports=s.match(/^(?:import[\s\S]*?;\n)+/);
  if(!imports) throw Error("Unable to locate route imports.");
  s=s.replace(imports[0],imports[0]+importLine+"\n");
}

if(!s.includes('"/broadcast-coordinator/:gameId/operator-notes"')) {
  const marker='  app.get(\n    "/broadcast-coordinator/:gameId/operator-timeline",';
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.5 operator timeline route missing.");

  const routes=`  app.get(
    "/broadcast-coordinator/:gameId/operator-notes",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

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
          notes:
            listBroadcastOperatorNotes(
              gameId,
              100,
            ),
        },
      };
    },
  );

  app.post(
    "/broadcast-coordinator/:gameId/operator-notes",
    async (request, reply) => {
      const gameId =
        (request.params as {
          gameId?: string;
        }).gameId?.trim();

      const body =
        request.body as {
          operator?: string;
          note?: string;
        };

      if (!gameId) {
        return reply.code(400).send({
          success: false,
          error:
            "Game ID is required.",
        });
      }

      try {
        const note =
          addBroadcastOperatorNote({
            gameId,
            operator:
              body.operator ??
              "",
            note:
              body.note ??
              "",
          });

        return {
          success: true,
          data: {
            note,
          },
        };
      } catch (error) {
        return reply.code(400).send({
          success: false,
          error:
            error instanceof Error
              ? error.message
              : "Unable to save operator note.",
        });
      }
    },
  );

`;

  s=s.slice(0,i)+routes+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

node <<'NODE'
const fs=require("fs");
const f="apps/dashboard/app/broadcast/operations/[gameId]/page.tsx";
let s=fs.readFileSync(f,"utf8");

if(!s.includes("type OperatorNote =")) {
  const marker="type OperatorTimelineEvent = {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("23.7 timeline type missing.");

  const type=`type OperatorNote = {
  id: string;
  gameId: string;
  operator: string;
  note: string;
  createdAt: string;
};

`;

  s=s.slice(0,i)+type+s.slice(i);
}

if(!s.includes("operatorNotes,")) {
  const marker=`  const [
    emergencyReason,
    setEmergencyReason,
  ] =
    useState("");`;

  if(!s.includes(marker)) throw Error("23.7 emergency state missing.");

  s=s.replace(
    marker,
`${marker}

  const [
    operatorNotes,
    setOperatorNotes,
  ] =
    useState<OperatorNote[]>(
      [],
    );

  const [
    handoffOperator,
    setHandoffOperator,
  ] =
    useState("");

  const [
    handoffNote,
    setHandoffNote,
  ] =
    useState("");`
  );
}

if(!s.includes("/operator-notes")) {
  const marker=`          timelineResponse,
        ] =
          await Promise.all([`;

  if(!s.includes(marker)) throw Error("23.7 Promise.all load block missing.");

  s=s.replace(
    marker,
`          timelineResponse,
          notesResponse,
        ] =
          await Promise.all([`
  );

  const close=`            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-timeline?limit=50\`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);`;

  if(!s.includes(close)) throw Error("23.7 timeline fetch block missing.");

  s=s.replace(
    close,
`            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-timeline?limit=50\`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-notes\`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);`
  );

  const jsonMarker=`        const timelineJson =
          await timelineResponse.json();`;

  if(!s.includes(jsonMarker)) throw Error("Timeline JSON parse missing.");

  s=s.replace(
    jsonMarker,
`${jsonMarker}

        const notesJson =
          await notesResponse.json();`
  );

  const stateMarker=`        setTimeline(
          timelineJson?.data?.events ??
          [],
        );`;

  if(!s.includes(stateMarker)) throw Error("Timeline state setter missing.");

  s=s.replace(
    stateMarker,
`${stateMarker}

        setOperatorNotes(
          notesJson?.data?.notes ??
          [],
        );`
  );
}

if(!s.includes("const saveOperatorNote =")) {
  const marker="  useEffect(() => {";
  const i=s.indexOf(marker);
  if(i<0) throw Error("Focus mode useEffect missing.");

  const fn=`  const saveOperatorNote =
    useCallback(
      async () => {
        if (
          !handoffOperator.trim() ||
          !handoffNote.trim()
        ) {
          setMessage(
            "Operator name and note are required.",
          );
          return;
        }

        setBusy(
          true,
        );

        try {
          const response =
            await fetch(
              \`\${API_BASE}/broadcast-coordinator/\${encodeURIComponent(gameId)}/operator-notes\`,
              {
                method:
                  "POST",
                headers: {
                  "Content-Type":
                    "application/json",
                },
                body:
                  JSON.stringify({
                    operator:
                      handoffOperator.trim(),
                    note:
                      handoffNote.trim(),
                  }),
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Unable to save operator note.",
            );
          }

          setHandoffNote(
            "",
          );

          setMessage(
            "Operator note saved.",
          );

          await load();
        } catch (error) {
          setMessage(
            error instanceof Error
              ? error.message
              : "Unable to save operator note.",
          );
        } finally {
          setBusy(
            false,
          );
        }
      },
      [
        gameId,
        handoffNote,
        handoffOperator,
        load,
      ],
    );

`;

  s=s.slice(0,i)+fn+s.slice(i);
}

if(!s.includes("Shift Handoff Notes")) {
  const marker=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">Operator Timeline</div>`;

  const i=s.indexOf(marker);
  if(i<0) throw Error("23.7 operator timeline section missing.");

  const block=`          <section className="mt-4 rounded-xl border border-slate-800 p-5">
            <div className="text-sm font-semibold">
              Shift Handoff Notes
            </div>

            <p className="mt-1 text-xs text-slate-500">
              Operational context only. Notes do not affect broadcast state or automation.
            </p>

            <div className="mt-3 grid gap-3 md:grid-cols-2">
              <input
                value={handoffOperator}
                onChange={(event) =>
                  setHandoffOperator(
                    event.target.value,
                  )
                }
                placeholder="Operator name"
                className="rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
              />

              <button
                type="button"
                disabled={
                  busy ||
                  !handoffOperator.trim() ||
                  !handoffNote.trim()
                }
                onClick={() =>
                  void saveOperatorNote()
                }
                className="rounded-lg border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Save Handoff Note
              </button>
            </div>

            <textarea
              value={handoffNote}
              onChange={(event) =>
                setHandoffNote(
                  event.target.value,
                )
              }
              placeholder="Current issue, workaround, expected next action, or handoff context…"
              rows={4}
              className="mt-3 w-full rounded-lg border border-slate-800 bg-transparent px-3 py-2 text-xs"
            />

            <div className="mt-4 space-y-2">
              {operatorNotes.length === 0 ? (
                <div className="text-xs text-slate-500">
                  No handoff notes recorded.
                </div>
              ) : (
                operatorNotes.map(
                  (note) => (
                    <div
                      key={note.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex flex-wrap justify-between gap-2">
                        <div className="text-xs font-semibold">
                          {note.operator}
                        </div>

                        <div className="text-xs text-slate-500">
                          {note.createdAt}
                        </div>
                      </div>

                      <div className="mt-2 whitespace-pre-wrap text-xs text-slate-400">
                        {note.note}
                      </div>
                    </div>
                  ),
                )
              )}
            </div>
          </section>

`;

  s=s.slice(0,i)+block+s.slice(i);
}

fs.writeFileSync(f,s);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 23.8 — Operator notes / shift handoff context

Focus Mode now supports persistent operator handoff notes.

API:

```text
GET  /broadcast-coordinator/:gameId/operator-notes
POST /broadcast-coordinator/:gameId/operator-notes
```

Each note contains:

```text
gameId
operator
note
createdAt
```

Notes are stored in the shared SportsOS data directory:

```text
broadcast-operator-notes.json
```

The notes store is bounded to the newest 2500 notes globally.

Operator notes are context only. They do not modify:

- coordinator intent
- go-live state
- encoder state
- retry state
- incident state
- automation decisions
- authoritative game state

Focus Mode displays newest notes first and refreshes them with the rest of the broadcast workspace.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 23.8 operator notes / shift handoff context", () => {
  const service=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastOperatorNotes.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route=
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionCoordinator.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const focus=
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/operations/[gameId]/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("persists operator notes in shared SportsOS data storage",()=> {
    expect(service).toContain("SPORTSOS_DATA_DIR");
    expect(service).toContain("broadcast-operator-notes.json");
    expect(service).toContain("2500");
  });

  it("requires operator and note text",()=> {
    expect(service).toContain("Operator name is required.");
    expect(service).toContain("Operator note is required.");
  });

  it("provides notes API",()=> {
    expect(route).toContain('"/broadcast-coordinator/:gameId/operator-notes"');
    expect(route).toContain("listBroadcastOperatorNotes");
    expect(route).toContain("addBroadcastOperatorNote");
  });

  it("provides shift handoff notes UI",()=> {
    expect(focus).toContain("Shift Handoff Notes");
    expect(focus).toContain("Save Handoff Note");
    expect(focus).toContain("operatorNotes");
  });

  it("does not let notes control broadcast state",()=> {
    expect(service).not.toContain("startEncoderRuntime");
    expect(service).not.toContain("stopEncoderRuntime");
    expect(service).not.toContain("setBroadcastCoordinatorIntent");
    expect(service).not.toContain("markGoLive");
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 23.8 installed"
echo "============================================================"
echo "Added:"
echo "  - persistent operator handoff notes"
echo "  - GET/POST notes API"
echo "  - operator identity + timestamp"
echo "  - Focus Mode handoff UI"
echo "  - bounded notes storage"
echo "  - no effect on broadcast control state"
echo "  - Milestone 23.8 regression tests"
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
echo "  Milestone 23.9 - Operator Shift Summary / Handoff Snapshot"
