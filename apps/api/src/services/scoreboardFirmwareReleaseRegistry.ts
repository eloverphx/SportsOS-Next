import fs from "node:fs";
import path from "node:path";

import type {
  FirmwareReleaseChannel,
  FirmwareReleaseTarget,
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

type RegistryStore = {
  version: 1;
  releases: ScoreboardFirmwareRelease[];
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
    "scoreboard-firmware-releases.json",
  );

let store =
  loadStore();

function loadStore(): RegistryStore {
  try {
    const raw =
      fs.readFileSync(
        STORE_FILE,
        "utf8",
      );

    const parsed =
      JSON.parse(raw) as RegistryStore;

    if (
      parsed?.version !== 1 ||
      !Array.isArray(
        parsed.releases,
      )
    ) {
      throw new Error(
        "Invalid firmware release registry.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      releases: [],
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

function versionParts(
  version: string,
): number[] {
  return version
    .replace(/^v/i, "")
    .split(".")
    .map((part) => {
      const parsed =
        Number.parseInt(
          part,
          10,
        );

      return Number.isFinite(
        parsed,
      )
        ? parsed
        : 0;
    });
}

function compareVersions(
  left: string,
  right: string,
): number {
  const a =
    versionParts(left);

  const b =
    versionParts(right);

  const length =
    Math.max(
      a.length,
      b.length,
    );

  for (
    let index = 0;
    index < length;
    index += 1
  ) {
    const delta =
      (a[index] ?? 0) -
      (b[index] ?? 0);

    if (delta !== 0) {
      return delta;
    }
  }

  return 0;
}

export function registerFirmwareRelease(
  release: ScoreboardFirmwareRelease,
): ScoreboardFirmwareRelease {
  const existingIndex =
    store.releases.findIndex(
      (candidate) =>
        candidate.releaseId ===
        release.releaseId,
    );

  if (existingIndex >= 0) {
    store.releases[
      existingIndex
    ] = release;
  } else {
    store.releases.push(
      release,
    );
  }

  persistStore();

  return release;
}

export function listFirmwareReleases(input?: {
  channel?: FirmwareReleaseChannel;
  target?: FirmwareReleaseTarget;
}): ScoreboardFirmwareRelease[] {
  return store.releases
    .filter(
      (release) =>
        (!input?.channel ||
          release.channel ===
            input.channel) &&
        (!input?.target ||
          release.target ===
            input.target),
    )
    .sort(
      (a, b) =>
        compareVersions(
          b.version,
          a.version,
        ),
    );
}

export function getFirmwareRelease(
  releaseId: string,
): ScoreboardFirmwareRelease | null {
  return (
    store.releases.find(
      (release) =>
        release.releaseId ===
        releaseId,
    ) ?? null
  );
}

export function getLatestCompatibleFirmwareRelease(input: {
  currentVersion: string;
  channel: FirmwareReleaseChannel;
  target: FirmwareReleaseTarget;
}): ScoreboardFirmwareRelease | null {
  const candidates =
    listFirmwareReleases({
      channel:
        input.channel,
      target:
        input.target,
    });

  for (const release of candidates) {
    if (
      release.minimumCurrentVersion &&
      compareVersions(
        input.currentVersion,
        release.minimumCurrentVersion,
      ) < 0
    ) {
      continue;
    }

    if (
      compareVersions(
        release.version,
        input.currentVersion,
      ) <= 0
    ) {
      continue;
    }

    return release;
  }

  return null;
}
