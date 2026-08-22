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
        input.checks.map(
          (check) => ({
            ...check,
          }),
        ),
      startedAt:
        input.startedAt,
      completedAt:
        new Date().toISOString(),
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
