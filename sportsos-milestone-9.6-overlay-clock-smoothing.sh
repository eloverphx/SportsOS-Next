#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="9.6-overlay-clock-smoothing"
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
  "$ROOT/apps"
do
  [[ -e "$required" ]] || {
    echo "ERROR: repository safety marker missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

CLIENT="apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx"
CLOCK_LIB="apps/dashboard/lib/broadcast-overlay-clock.ts"
CLOCK_TEST="apps/dashboard/test/broadcast-overlay-clock-9.6.test.ts"

[[ -f "$CLIENT" ]] || {
  echo "ERROR: Milestone 9.5 browser overlay missing: $CLIENT" >&2
  exit 1
}

mkdir -p \
  "$BACKUP_DIR/$(dirname "$CLIENT")" \
  "$BACKUP_DIR/$(dirname "$CLOCK_LIB")" \
  "$BACKUP_DIR/$(dirname "$CLOCK_TEST")"

for file in "$CLIENT" "$CLOCK_LIB" "$CLOCK_TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$CLOCK_LIB" <<'EOF'
export type OverlayClockAnchor = {
  remainingMs: number;
  running: boolean;
  capturedAtMs: number;
};

export function deriveSmoothedRemainingMs(
  anchor: OverlayClockAnchor,
  nowMs: number,
): number {
  const remaining = Math.max(0, anchor.remainingMs);

  if (!anchor.running) {
    return remaining;
  }

  const elapsed = Math.max(
    0,
    nowMs - anchor.capturedAtMs,
  );

  return Math.max(0, remaining - elapsed);
}

export function formatOverlayClock(
  remainingMs: number,
): string {
  const clamped = Math.max(0, remainingMs);

  if (clamped < 60_000) {
    const tenths = Math.floor(clamped / 100);
    const seconds = Math.floor(tenths / 10);
    const decimal = tenths % 10;

    return `${seconds}.${decimal}`;
  }

  const totalSeconds = Math.floor(clamped / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/components/broadcast/BroadcastOverlayClient.tsx";

let text = fs.readFileSync(file, "utf8");

const contractImport = `import type {
  BroadcastOverlaySnapshot,
} from "../../lib/broadcast-overlay-contract";`;

if (!text.includes('from "../../lib/broadcast-overlay-clock"')) {
  if (!text.includes(contractImport)) {
    throw new Error("Overlay contract import anchor not found.");
  }

  text = text.replace(
    contractImport,
`${contractImport}
import {
  deriveSmoothedRemainingMs,
  formatOverlayClock,
} from "../../lib/broadcast-overlay-clock";`,
  );
}

const oldFormat = `function formatClock(remainingMs: number): string {
  const totalSeconds = Math.max(
    0,
    Math.floor(remainingMs / 1000),
  );

  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;

  return \`\${minutes}:\${seconds.toString().padStart(2, "0")}\`;
}

`;

if (text.includes(oldFormat)) {
  text = text.replace(oldFormat, "");
}

if (!text.includes("const [clockNowMs, setClockNowMs]")) {
  const stateAnchor = `  const [realtimeConnected, setRealtimeConnected] =
    useState(false);

  const loadInFlight = useRef(false);`;

  if (!text.includes(stateAnchor)) {
    throw new Error("Realtime state anchor not found.");
  }

  text = text.replace(
    stateAnchor,
`  const [realtimeConnected, setRealtimeConnected] =
    useState(false);
  const [clockNowMs, setClockNowMs] = useState(
    () => Date.now(),
  );
  const clockAnchorRef = useRef<{
    remainingMs: number;
    running: boolean;
    capturedAtMs: number;
  } | null>(null);

  const loadInFlight = useRef(false);`,
  );
}

const snapshotAnchor = `        if (active) {
          setSnapshot(payload);
          setError(null);
        }`;

if (!text.includes("clockAnchorRef.current = {")) {
  if (!text.includes(snapshotAnchor)) {
    throw new Error("Snapshot update anchor not found.");
  }

  text = text.replace(
    snapshotAnchor,
`        if (active) {
          setSnapshot(payload);
          clockAnchorRef.current = {
            remainingMs: payload.clock.remainingMs,
            running: payload.clock.running,
            capturedAtMs: Date.now(),
          };
          setClockNowMs(Date.now());
          setError(null);
        }`,
  );
}

if (!text.includes("const displayedRemainingMs = useMemo(")) {
  const effectAnchor = `  }, [gameId]);

  const powerPlayLabel = useMemo(() => {`;

  if (!text.includes(effectAnchor)) {
    throw new Error("Primary effect end anchor not found.");
  }

  text = text.replace(
    effectAnchor,
`  }, [gameId]);

  useEffect(() => {
    const timer = setInterval(() => {
      setClockNowMs(Date.now());
    }, 100);

    return () => {
      clearInterval(timer);
    };
  }, []);

  const displayedRemainingMs = useMemo(() => {
    const anchor = clockAnchorRef.current;

    if (!anchor) {
      return snapshot?.clock.remainingMs ?? 0;
    }

    return deriveSmoothedRemainingMs(
      anchor,
      clockNowMs,
    );
  }, [clockNowMs, snapshot]);

  const powerPlayLabel = useMemo(() => {`,
  );
}

text = text.replaceAll(
  "formatClock(",
  "formatOverlayClock(",
);

text = text.replace(
  "{formatOverlayClock(snapshot.clock.remainingMs)}",
  "{formatOverlayClock(displayedRemainingMs)}",
);

fs.writeFileSync(file, text);
NODE

cat > "$CLOCK_TEST" <<'EOF'
import { describe, expect, it } from "vitest";
import {
  deriveSmoothedRemainingMs,
  formatOverlayClock,
} from "../lib/broadcast-overlay-clock";

describe("Milestone 9.6 overlay clock smoothing", () => {
  it("holds a paused authoritative clock steady", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 120000,
          running: false,
          capturedAtMs: 1000,
        },
        9000,
      ),
    ).toBe(120000);
  });

  it("subtracts elapsed wall time while the clock is running", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 120000,
          running: true,
          capturedAtMs: 1000,
        },
        3500,
      ),
    ).toBe(117500);
  });

  it("never displays a negative clock", () => {
    expect(
      deriveSmoothedRemainingMs(
        {
          remainingMs: 1000,
          running: true,
          capturedAtMs: 0,
        },
        5000,
      ),
    ).toBe(0);
  });

  it("formats normal time as minutes and seconds", () => {
    expect(formatOverlayClock(125000)).toBe("2:05");
  });

  it("formats under one minute with tenths", () => {
    expect(formatOverlayClock(59700)).toBe("59.7");
    expect(formatOverlayClock(9400)).toBe("9.4");
  });

  it("renders zero safely", () => {
    expect(formatOverlayClock(0)).toBe("0.0");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 9.6 installed"
echo "============================================================"
echo
echo "Safety:"
echo "  - canonical root verified"
echo "  - .git / package.json / apps verified"
echo "  - refuses alternate roots"
echo
echo "Added:"
echo "  - authoritative clock anchor model"
echo "  - smooth local countdown between realtime snapshots"
echo "  - paused-clock hold behavior"
echo "  - under-1-minute tenths display"
echo "  - zero clamp"
echo "  - 100ms render cadence"
echo "  - Milestone 9.6 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Next after green:"
echo "  Milestone 9.7 - Broadcast Overlay Themes / Branding"
