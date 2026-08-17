#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.1.1-testing-override-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

WORKSPACE="apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx"
TEST_FILE="apps/dashboard/test/tournament-game-operations-7.1.test.ts"
OVERRIDE_LIB="apps/dashboard/lib/testing-override.ts"

for file in "$WORKSPACE" "$TEST_FILE"; do
  [[ -f "$file" ]] || { echo "ERROR: missing $file" >&2; exit 1; }
done

mkdir -p "$BACKUP_DIR/$(dirname "$WORKSPACE")" \
         "$BACKUP_DIR/$(dirname "$TEST_FILE")" \
         "$BACKUP_DIR/$(dirname "$OVERRIDE_LIB")"

cp -a "$WORKSPACE" "$BACKUP_DIR/$WORKSPACE"
cp -a "$TEST_FILE" "$BACKUP_DIR/$TEST_FILE"
[[ -f "$OVERRIDE_LIB" ]] && cp -a "$OVERRIDE_LIB" "$BACKUP_DIR/$OVERRIDE_LIB"

cat > "$OVERRIDE_LIB" <<'EOF'
export const SPORTSOS_TEST_OVERRIDE_STORAGE_KEY =
  "sportsos:tournament-game-operations:test-override";

export const SPORTSOS_TEST_OVERRIDE_EVENT =
  "sportsos:test-override-changed";

export function isLocalTestingHost(hostname: string): boolean {
  const host = hostname.trim().toLowerCase();

  if (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "::1" ||
    host.endsWith(".local")
  ) {
    return true;
  }

  if (/^10\./.test(host) || /^192\.168\./.test(host)) {
    return true;
  }

  const match = host.match(/^172\.(\d{1,3})\./);
  if (match) {
    const secondOctet = Number(match[1]);
    return secondOctet >= 16 && secondOctet <= 31;
  }

  return false;
}

export function canUseTestingOverride(hostname: string): boolean {
  return (
    process.env.NEXT_PUBLIC_SPORTSOS_ENABLE_TEST_OVERRIDE === "true" ||
    isLocalTestingHost(hostname)
  );
}

export function readTestingOverride(
  storage: Pick<Storage, "getItem">,
): boolean {
  return storage.getItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY) === "enabled";
}

export function writeTestingOverride(
  storage: Pick<Storage, "setItem" | "removeItem">,
  enabled: boolean,
): void {
  if (enabled) storage.setItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY, "enabled");
  else storage.removeItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY);
}

export function effectiveReadiness(
  actualReady: boolean,
  testingOverrideEnabled: boolean,
): boolean {
  return actualReady || testingOverrideEnabled;
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/dashboard/components/tournament/TournamentGameOperationsWorkspace.tsx";
let text = fs.readFileSync(file, "utf8");

function replaceOnce(label, search, replacement) {
  if (!text.includes(search)) throw new Error(`Expected ${label} anchor not found.`);
  text = text.replace(search, replacement);
}

if (!text.includes('from "../../lib/testing-override";')) {
  replaceOnce(
    "game operations import",
`import {
  extractTournamentGame,
  extractTournamentGameList,
  readinessCount,
  type TournamentGameOperationsGame,
} from "../../lib/tournament-game-operations";`,
`import {
  extractTournamentGame,
  extractTournamentGameList,
  readinessCount,
  type TournamentGameOperationsGame,
} from "../../lib/tournament-game-operations";
import {
  SPORTSOS_TEST_OVERRIDE_EVENT,
  canUseTestingOverride,
  effectiveReadiness,
  readTestingOverride,
  writeTestingOverride,
} from "../../lib/testing-override";`
  );
}

if (!text.includes("testingOverrideAvailable")) {
  replaceOnce(
    "message state",
`  const [message, setMessage] = useState<string | null>(null);`,
`  const [message, setMessage] = useState<string | null>(null);
  const [testingOverrideAvailable, setTestingOverrideAvailable] =
    useState(false);
  const [testingOverrideEnabled, setTestingOverrideEnabled] =
    useState(false);`
  );
}

if (!text.includes("handleOverrideChange")) {
  replaceOnce(
    "load effect",
`  useEffect(() => {
    let active = true;

    async function loadGames() {`,
`  useEffect(() => {
    const available = canUseTestingOverride(window.location.hostname);
    setTestingOverrideAvailable(available);
    setTestingOverrideEnabled(
      available ? readTestingOverride(window.localStorage) : false,
    );

    const handleOverrideChange = () => {
      setTestingOverrideEnabled(
        available ? readTestingOverride(window.localStorage) : false,
      );
    };

    window.addEventListener(SPORTSOS_TEST_OVERRIDE_EVENT, handleOverrideChange);
    return () => {
      window.removeEventListener(
        SPORTSOS_TEST_OVERRIDE_EVENT,
        handleOverrideChange,
      );
    };
  }, []);

  useEffect(() => {
    let active = true;

    async function loadGames() {`
  );
}

if (!text.includes("effectiveReadinessCount")) {
  replaceOnce(
    "readiness memo",
`  const selectedReadiness = useMemo(
    () => (selectedGame ? readinessCount(selectedGame) : null),
    [selectedGame],
  );`,
`  const selectedReadiness = useMemo(
    () => (selectedGame ? readinessCount(selectedGame) : null),
    [selectedGame],
  );

  const effectiveReadinessCount = useMemo(() => {
    if (!selectedReadiness) return null;
    return testingOverrideEnabled
      ? { passed: selectedReadiness.total, total: selectedReadiness.total }
      : selectedReadiness;
  }, [selectedReadiness, testingOverrideEnabled]);

  const toggleTestingOverride = () => {
    if (!testingOverrideAvailable) return;
    const next = !testingOverrideEnabled;
    writeTestingOverride(window.localStorage, next);
    setTestingOverrideEnabled(next);
    window.dispatchEvent(new Event(SPORTSOS_TEST_OVERRIDE_EVENT));
  };`
  );
}

if (!text.includes('data-testid="testing-override-panel"')) {
  const closeHeader = text.indexOf("</header>");
  if (closeHeader < 0) throw new Error("Could not find </header> in workspace.");

  const insertAt = closeHeader + "</header>".length;
  const panel = `

      {testingOverrideAvailable ? (
        <div
          data-testid="testing-override-panel"
          className={
            testingOverrideEnabled
              ? "rounded-xl border border-amber-500/70 bg-amber-950/30 p-4"
              : "rounded-xl border border-slate-800 bg-slate-950/40 p-4"
          }
        >
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="font-semibold text-slate-100">Testing override</h2>
                <span
                  data-testid="testing-override-status"
                  className={
                    testingOverrideEnabled
                      ? "rounded-full border border-amber-500/60 px-2 py-0.5 text-xs font-bold uppercase tracking-wide text-amber-300"
                      : "rounded-full border border-slate-700 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-slate-400"
                  }
                >
                  {testingOverrideEnabled ? "ENABLED" : "OFF"}
                </span>
              </div>
              <p className="mt-1 max-w-3xl text-sm text-slate-400">
                Local-development helper. Missing readiness information may be
                treated as satisfied for testing without changing stored game data.
              </p>
            </div>

            <button
              type="button"
              data-testid="testing-override-toggle"
              onClick={toggleTestingOverride}
              className={
                testingOverrideEnabled
                  ? "rounded-lg border border-amber-500/60 bg-amber-500/10 px-4 py-2 text-sm font-semibold text-amber-300"
                  : "rounded-lg border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-slate-200"
              }
            >
              {testingOverrideEnabled
                ? "Disable testing override"
                : "Enable testing override"}
            </button>
          </div>

          {testingOverrideEnabled ? (
            <p className="mt-3 text-xs font-semibold text-amber-300">
              TESTING OVERRIDE ACTIVE — missing readiness data may be bypassed.
            </p>
          ) : null}
        </div>
      ) : null}`;
  text = text.slice(0, insertAt) + panel + text.slice(insertAt);
}

text = text.replace(
  "{selectedReadiness?.passed}/{selectedReadiness?.total}",
  "{effectiveReadinessCount?.passed}/{effectiveReadinessCount?.total}"
);

for (const field of ["teamsAssigned", "rinkAssigned", "scheduledStartAssigned"]) {
  const oldValue = `ready={selectedGame.readiness.${field}}`;
  if (text.includes(oldValue)) {
    text = text.replace(
      oldValue,
`ready={effectiveReadiness(
                    selectedGame.readiness.${field},
                    testingOverrideEnabled,
                  )}`
    );
  }
}

fs.writeFileSync(file, text);
NODE

if ! grep -Fq 'describe("Milestone 7.1.1 testing override"' "$TEST_FILE"; then
cat >> "$TEST_FILE" <<'EOF'

describe("Milestone 7.1.1 testing override", () => {
  it("recognizes local testing hosts", async () => {
    const { isLocalTestingHost } = await import("../lib/testing-override");

    expect(isLocalTestingHost("localhost")).toBe(true);
    expect(isLocalTestingHost("127.0.0.1")).toBe(true);
    expect(isLocalTestingHost("192.168.5.3")).toBe(true);
    expect(isLocalTestingHost("10.0.0.25")).toBe(true);
    expect(isLocalTestingHost("172.16.1.10")).toBe(true);
    expect(isLocalTestingHost("172.31.255.1")).toBe(true);
    expect(isLocalTestingHost("172.32.0.1")).toBe(false);
    expect(isLocalTestingHost("sports.example.com")).toBe(false);
  });

  it("persists testing override state", async () => {
    const {
      readTestingOverride,
      writeTestingOverride,
      SPORTSOS_TEST_OVERRIDE_STORAGE_KEY,
    } = await import("../lib/testing-override");

    const values = new Map<string, string>();
    const storage = {
      getItem(key: string) {
        return values.get(key) ?? null;
      },
      setItem(key: string, value: string) {
        values.set(key, value);
      },
      removeItem(key: string) {
        values.delete(key);
      },
    };

    expect(readTestingOverride(storage)).toBe(false);
    writeTestingOverride(storage, true);
    expect(values.get(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY)).toBe("enabled");
    expect(readTestingOverride(storage)).toBe(true);
    writeTestingOverride(storage, false);
    expect(readTestingOverride(storage)).toBe(false);
  });

  it("bypasses readiness only when enabled", async () => {
    const { effectiveReadiness } = await import("../lib/testing-override");

    expect(effectiveReadiness(false, false)).toBe(false);
    expect(effectiveReadiness(true, false)).toBe(true);
    expect(effectiveReadiness(false, true)).toBe(true);
    expect(effectiveReadiness(true, true)).toBe(true);
  });
});
EOF
fi

echo
echo "Milestone 7.1.1 testing override repair applied."
echo "Backup: $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
