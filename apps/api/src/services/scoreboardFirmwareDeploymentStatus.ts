import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardFirmwareUpdateReport,
} from "@sportsos/core";

type DeploymentStore = {
  version: 1;
  reports: ScoreboardFirmwareUpdateReport[];
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
    "scoreboard-firmware-deployments.json",
  );

let store =
  loadStore();

function loadStore(): DeploymentStore {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as DeploymentStore;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.reports,
      )
    ) {
      throw new Error(
        "Invalid deployment status store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      reports: [],
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

export function recordFirmwareDeploymentStatus(
  report: ScoreboardFirmwareUpdateReport,
): ScoreboardFirmwareUpdateReport {
  store.reports.push(
    report,
  );

  if (
    store.reports.length >
    1000
  ) {
    store.reports =
      store.reports.slice(
        -1000,
      );
  }

  persistStore();

  return report;
}

export function listFirmwareDeploymentReports(input?: {
  deviceId?: string;
  releaseId?: string;
}): ScoreboardFirmwareUpdateReport[] {
  return store.reports
    .filter(
      (report) =>
        (!input?.deviceId ||
          report.deviceId ===
            input.deviceId) &&
        (!input?.releaseId ||
          report.releaseId ===
            input.releaseId),
    )
    .sort(
      (a, b) =>
        b.reportedAt.localeCompare(
          a.reportedAt,
        ),
    );
}

export function getLatestFirmwareDeploymentStatus(
  deviceId: string,
): ScoreboardFirmwareUpdateReport | null {
  return (
    listFirmwareDeploymentReports({
      deviceId,
    })[0] ?? null
  );
}
