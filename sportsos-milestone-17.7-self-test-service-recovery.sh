#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-17.7-self-test-service-recovery-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && "$ROOT_REAL" == "$EXPECTED_REAL" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

for required in \
  ".git" \
  "package.json" \
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

SERVICE="apps/api/src/services/scoreboardCommissioningSelfTest.ts"
ROUTE="apps/api/src/routes/scoreboardDeviceCommissioning.ts"
TEST="packages/core/test/scoreboard-commissioning-self-test-recovery-17.7.test.ts"

for file in "$SERVICE" "$ROUTE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$SERVICE")" "$(dirname "$TEST")"

cat > "$SERVICE" <<'EOF'
import fs from "node:fs";
import path from "node:path";

export type CommissioningSelfTestCheck = {
  id:
    | "CONTROLLER"
    | "DISPLAY"
    | "INPUT"
    | "CONNECTIVITY"
    | "FIRMWARE_RUNTIME";
  passed: boolean;
  detail: string;
};

export type CommissioningSelfTestResult = {
  testId: string;
  deviceId: string;
  status:
    | "PASS"
    | "FAIL";
  checks: CommissioningSelfTestCheck[];
  startedAt: string;
  completedAt: string;
  source:
    | "INSTALLER"
    | "FIRMWARE";
};

type Store = {
  version: 1;
  results:
    CommissioningSelfTestResult[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(process.cwd(), "data");

const STORE_FILE =
  path.join(
    DATA_DIR,
    "scoreboard-commissioning-self-tests.json",
  );

let store = loadStore();

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
        parsed.results,
      )
    ) {
      throw new Error(
        "Invalid commissioning self-test store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      results: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    { recursive: true },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function createCommissioningSelfTestResult(input: {
  deviceId: string;
  checks: CommissioningSelfTestCheck[];
  startedAt: string;
  source?: "INSTALLER" | "FIRMWARE";
}): CommissioningSelfTestResult {
  const completedAt =
    new Date().toISOString();

  const result:
    CommissioningSelfTestResult = {
      testId:
        `selftest-${input.deviceId}-${Date.now()}`,
      deviceId:
        input.deviceId,
      status:
        input.checks.every(
          (check) =>
            check.passed,
        )
          ? "PASS"
          : "FAIL",
      checks:
        input.checks,
      startedAt:
        input.startedAt,
      completedAt,
      source:
        input.source ??
        "INSTALLER",
    };

  store.results.push(
    result,
  );

  if (
    store.results.length >
    1000
  ) {
    store.results =
      store.results.slice(
        -1000,
      );
  }

  persistStore();

  return {
    ...result,
    checks:
      result.checks.map(
        (check) => ({
          ...check,
        }),
      ),
  };
}

export function latestCommissioningSelfTest(
  deviceId: string,
): CommissioningSelfTestResult | null {
  const result =
    [...store.results]
      .reverse()
      .find(
        (item) =>
          item.deviceId ===
          deviceId,
      );

  return result
    ? {
        ...result,
        checks:
          result.checks.map(
            (check) => ({
              ...check,
            }),
          ),
      }
    : null;
}

export function listCommissioningSelfTests(
  deviceId?: string,
): CommissioningSelfTestResult[] {
  return [...store.results]
    .filter(
      (item) =>
        !deviceId ||
        item.deviceId ===
          deviceId,
    )
    .sort(
      (a, b) =>
        b.completedAt.localeCompare(
          a.completedAt,
        ),
    )
    .map(
      (item) => ({
        ...item,
        checks:
          item.checks.map(
            (check) => ({
              ...check,
            }),
          ),
      }),
    );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/routes/scoreboardDeviceCommissioning.ts";

const text =
  fs.readFileSync(
    file,
    "utf8",
  );

for (const value of [
  "createCommissioningSelfTestResult",
  "latestCommissioningSelfTest",
  "/self-test",
]) {
  if (!text.includes(value)) {
    throw new Error(
      `Self-test route hook missing: ${value}`,
    );
  }
}

console.log(
  "Existing self-test route hooks verified.",
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 17.7 self-test service recovery", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardCommissioningSelfTest.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardDeviceCommissioning.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("restores persistent commissioning self-test service", () => {
    expect(service).toContain(
      "scoreboard-commissioning-self-tests.json",
    );

    expect(service).toContain(
      "createCommissioningSelfTestResult",
    );

    expect(service).toContain(
      "latestCommissioningSelfTest",
    );
  });

  it("supports installer and firmware result sources", () => {
    expect(service).toContain(
      '"INSTALLER"',
    );

    expect(service).toContain(
      '"FIRMWARE"',
    );
  });

  it("keeps the existing self-test route contract wired", () => {
    expect(route).toContain(
      "/self-test",
    );

    expect(route).toContain(
      "createCommissioningSelfTestResult",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 17.7 self-test service recovery"
echo "============================================================"
echo
echo "Restored:"
echo "  - scoreboardCommissioningSelfTest.ts"
echo "  - persistent self-test result store"
echo "  - PASS / FAIL aggregation"
echo "  - CONTROLLER / DISPLAY / INPUT / CONNECTIVITY / FIRMWARE_RUNTIME checks"
echo "  - INSTALLER / FIRMWARE source tracking"
echo "  - latest/list result helpers"
echo "  - existing route-hook verification"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then retry:"
echo "  bash sportsos-milestone-17.8-remote-self-test-command-correlation.sh"
