import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardFirmwareRelease,
} from "@sportsos/core";

import {
  registerFirmwareRelease,
} from "./scoreboardFirmwareReleaseRegistry.js";

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const ARTIFACT_DIR =
  path.join(
    DATA_DIR,
    "scoreboard-firmware-artifacts",
  );

export type ImportedFirmwareArtifact = {
  release: ScoreboardFirmwareRelease;
  artifactPath: string;
};

function sha256File(
  filePath: string,
): string {
  const hash =
    crypto.createHash("sha256");

  const contents =
    fs.readFileSync(
      filePath,
    );

  hash.update(
    contents,
  );

  return hash.digest(
    "hex",
  );
}

export function importFirmwareReleaseDirectory(
  releaseDirectory: string,
): ImportedFirmwareArtifact {
  const manifestPath =
    path.join(
      releaseDirectory,
      "release.json",
    );

  if (!fs.existsSync(manifestPath)) {
    throw new Error(
      "release.json is missing.",
    );
  }

  const manifest =
    JSON.parse(
      fs.readFileSync(
        manifestPath,
        "utf8",
      ),
    ) as ScoreboardFirmwareRelease;

  if (
    !manifest.releaseId ||
    !manifest.firmwareFile ||
    !manifest.firmwareSha256 ||
    !manifest.firmwareSizeBytes
  ) {
    throw new Error(
      "Release manifest is incomplete.",
    );
  }

  const sourceArtifact =
    path.join(
      releaseDirectory,
      manifest.firmwareFile,
    );

  if (!fs.existsSync(sourceArtifact)) {
    throw new Error(
      "Firmware artifact is missing.",
    );
  }

  const actualSize =
    fs.statSync(
      sourceArtifact,
    ).size;

  if (
    actualSize !==
    manifest.firmwareSizeBytes
  ) {
    throw new Error(
      "Firmware artifact size does not match release manifest.",
    );
  }

  const actualSha256 =
    sha256File(
      sourceArtifact,
    );

  if (
    actualSha256.toLowerCase() !==
    manifest.firmwareSha256.toLowerCase()
  ) {
    throw new Error(
      "Firmware artifact SHA-256 does not match release manifest.",
    );
  }

  const releaseArtifactDir =
    path.join(
      ARTIFACT_DIR,
      manifest.releaseId,
    );

  fs.mkdirSync(
    releaseArtifactDir,
    {
      recursive: true,
    },
  );

  const destination =
    path.join(
      releaseArtifactDir,
      "firmware.bin",
    );

  const temp =
    `${destination}.tmp`;

  fs.copyFileSync(
    sourceArtifact,
    temp,
  );

  fs.renameSync(
    temp,
    destination,
  );

  fs.writeFileSync(
    path.join(
      releaseArtifactDir,
      "release.json",
    ),
    JSON.stringify(
      manifest,
      null,
      2,
    ),
    "utf8",
  );

  registerFirmwareRelease(
    manifest,
  );

  return {
    release:
      manifest,
    artifactPath:
      destination,
  };
}

export function getFirmwareArtifactPath(
  releaseId: string,
): string | null {
  const artifact =
    path.join(
      ARTIFACT_DIR,
      releaseId,
      "firmware.bin",
    );

  return fs.existsSync(
    artifact,
  )
    ? artifact
    : null;
}
