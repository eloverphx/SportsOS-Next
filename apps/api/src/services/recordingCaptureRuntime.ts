import { createHash } from "node:crypto";
import { spawn, type ChildProcess } from "node:child_process";
import { createReadStream } from "node:fs";
import { mkdir, readdir, rm, stat } from "node:fs/promises";
import path from "node:path";
import type { ResultSetHeader, RowDataPacket } from "mysql2/promise";
import { config } from "@sportsos/config";
import { pool } from "../infrastructure/database.js";
import { minio } from "../infrastructure/minio.js";
import {
  buildRecordingCaptureArgs,
  buildRecordingRemuxArgs,
  buildRecordingTranscodeArgs,
} from "./recordingCaptureFfmpeg.js";

type CaptureEntry = {
  child: ChildProcess;
  capturePath: string;
  stderrTail: string;
};

interface RecordingRow extends RowDataPacket {
  id: number | string;
  organization_id: number | string;
  owner_user_id: number | string | null;
  started_at: Date | string | null;
  media_asset_id: number | string | null;
  status: string;
}

export type RecordingCaptureFinalizeResult =
  | {
      finalized: true;
      recordingId: number;
      mediaAssetId: number;
      objectKey: string;
      durationMs: number;
    }
  | {
      finalized: false;
      recordingId: number | null;
      reason: string;
    };

const captures = new Map<string, CaptureEntry>();

function ffmpegPath(): string {
  return process.env.SPORTSOS_FFMPEG_PATH?.trim() || process.env.FFMPEG_PATH?.trim() || "ffmpeg";
}

function ffprobePath(): string {
  return process.env.SPORTSOS_FFPROBE_PATH?.trim() || "ffprobe";
}

function resolveSourceUrl(gameId: string): string {
  const template = process.env.SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE?.trim();
  const direct = process.env.SPORTSOS_ENCODER_SOURCE_URL?.trim();
  const value = template ? template.replaceAll("{gameId}", encodeURIComponent(gameId)) : direct;

  if (!value) {
    throw new Error(
      "SPORTSOS_ENCODER_SOURCE_URL or SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE is required.",
    );
  }

  return value;
}

function safeGameId(gameId: string): string {
  return gameId.replace(/[^a-zA-Z0-9_-]/g, "_");
}

function captureDirectory(): string {
  const dataDir = process.env.SPORTSOS_DATA_DIR ?? path.resolve(process.cwd(), "data");
  return path.join(dataDir, "recordings", "in-progress");
}

async function runProcess(command: string, args: string[], captureStdout = false): Promise<string> {
  return await new Promise<string>((resolve, reject) => {
    const child = spawn(command, args, {
      shell: false,
      stdio: ["ignore", captureStdout ? "pipe" : "ignore", "pipe"],
      env: process.env,
    });

    let stdout = "";
    let stderr = "";

    child.stdout?.on("data", (chunk: Buffer) => {
      stdout = (stdout + chunk.toString("utf8")).slice(-32_000);
    });

    child.stderr?.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk.toString("utf8")).slice(-16_000);
    });

    child.once("error", reject);
    child.once("close", (code) => {
      if (code === 0) {
        resolve(stdout);
        return;
      }

      reject(
        new Error(
          `${path.basename(command)} exited with code ${code ?? "unknown"}${
            stderr ? `: ${stderr.trim()}` : ""
          }`,
        ),
      );
    });
  });
}

async function sha256File(filePath: string): Promise<string> {
  const hash = createHash("sha256");
  const stream = createReadStream(filePath);

  for await (const chunk of stream) {
    hash.update(chunk);
  }

  return hash.digest("hex");
}

async function probeDurationMs(filePath: string): Promise<number> {
  const stdout = await runProcess(
    ffprobePath(),
    [
      "-v",
      "error",
      "-show_entries",
      "format=duration",
      "-of",
      "default=noprint_wrappers=1:nokey=1",
      filePath,
    ],
    true,
  );

  const seconds = Number.parseFloat(stdout.trim());

  if (!Number.isFinite(seconds) || seconds <= 0) {
    throw new Error("Unable to determine finalized recording duration.");
  }

  return Math.max(1, Math.round(seconds * 1000));
}

async function latestDurableRecording(gameId: string): Promise<RecordingRow | null> {
  if (!/^[1-9]\d*$/.test(gameId)) {
    return null;
  }

  const [rows] = await pool.execute<RecordingRow[]>(
    `SELECT id, organization_id, owner_user_id, started_at, media_asset_id, status
       FROM recordings
       WHERE game_id = ?
         AND source = 'LIVE'
       ORDER BY id DESC
       LIMIT 1`,
    [Number(gameId)],
  );

  return rows[0] ?? null;
}

async function durableRecordingById(
  recordingId: number,
  gameId: string,
): Promise<RecordingRow | null> {
  if (!/^[1-9]\d*$/.test(gameId)) {
    return null;
  }

  const [rows] = await pool.execute<RecordingRow[]>(
    `SELECT id, organization_id, owner_user_id, started_at, media_asset_id, status
       FROM recordings
       WHERE id = ?
         AND game_id = ?
         AND source = 'LIVE'
       LIMIT 1`,
    [recordingId, Number(gameId)],
  );

  return rows[0] ?? null;
}

async function markLatestRecordingFailed(gameId: string, reason: string): Promise<void> {
  if (!/^[1-9]\d*$/.test(gameId)) {
    return;
  }

  await pool.execute(
    `UPDATE recordings
       SET status = 'FAILED'
       WHERE game_id = ?
         AND source = 'LIVE'
         AND status = 'PROCESSING'
         AND media_asset_id IS NULL
       ORDER BY id DESC
       LIMIT 1`,
    [Number(gameId)],
  );

  console.error(
    JSON.stringify({
      message: "Live recording capture finalization failed",
      gameId,
      error: reason.slice(0, 1000),
    }),
  );
}

export async function startRecordingCapture(gameId: string): Promise<void> {
  const current = captures.get(gameId);

  if (current && current.child.exitCode === null) {
    return;
  }

  const sourceUrl = resolveSourceUrl(gameId);
  const directory = captureDirectory();

  await mkdir(directory, { recursive: true });

  const durableRecording = await latestDurableRecording(gameId);

  if (
    !durableRecording ||
    durableRecording.media_asset_id != null ||
    durableRecording.status !== "RECORDING"
  ) {
    throw new Error(
      "Live recording capture requires an unfinalized durable RECORDING row for this game.",
    );
  }

  const recordingId = Number(durableRecording.id);
  const fileName = `recording-${recordingId}-game-${safeGameId(gameId)}-${Date.now()}.capture.mkv`;
  const capturePath = path.join(directory, fileName);

  const child = spawn(ffmpegPath(), buildRecordingCaptureArgs(sourceUrl, capturePath), {
    shell: false,
    stdio: ["ignore", "ignore", "pipe"],
    env: process.env,
  });

  const entry: CaptureEntry = {
    child,
    capturePath,
    stderrTail: "",
  };

  captures.set(gameId, entry);

  child.stderr?.on("data", (chunk: Buffer) => {
    entry.stderrTail = (entry.stderrTail + chunk.toString("utf8")).slice(-16_000);
  });

  await new Promise<void>((resolve, reject) => {
    child.once("spawn", resolve);
    child.once("error", reject);
  });

  console.info(
    JSON.stringify({
      message: "Live recording capture started",
      gameId,
      capturePath,
    }),
  );
}

async function stopCaptureProcess(gameId: string): Promise<CaptureEntry | null> {
  const entry = captures.get(gameId);

  if (!entry) {
    return null;
  }

  if (entry.child.exitCode === null) {
    entry.child.kill("SIGTERM");

    await new Promise<void>((resolve) => {
      let settled = false;

      const finish = () => {
        if (settled) return;
        settled = true;
        resolve();
      };

      entry.child.once("close", finish);

      const timer = setTimeout(() => {
        if (entry.child.exitCode === null) {
          entry.child.kill("SIGKILL");
        }
        finish();
      }, 10_000);

      timer.unref();
    });
  }

  captures.delete(gameId);
  return entry;
}

async function finalizeCaptureFile(capturePath: string): Promise<string> {
  const outputPath = `${capturePath}.mp4`;

  try {
    await runProcess(ffmpegPath(), buildRecordingRemuxArgs(capturePath, outputPath));
  } catch {
    await runProcess(ffmpegPath(), buildRecordingTranscodeArgs(capturePath, outputPath));
  }

  const output = await stat(outputPath);

  if (output.size <= 0) {
    throw new Error("Finalized live recording is empty.");
  }

  return outputPath;
}

async function persistFinalizedRecording(input: {
  recording: RecordingRow;
  outputPath: string;
  durationMs: number;
  checksumSha256: string;
  sizeBytes: number;
}): Promise<{ mediaAssetId: number; objectKey: string }> {
  const recordingId = Number(input.recording.id);
  const organizationId = Number(input.recording.organization_id);
  const ownerUserId =
    input.recording.owner_user_id == null ? null : Number(input.recording.owner_user_id);

  const capturedAt =
    input.recording.started_at == null
      ? new Date()
      : input.recording.started_at instanceof Date
        ? input.recording.started_at
        : new Date(input.recording.started_at);

  const year = capturedAt.getUTCFullYear();
  const objectKey = `recordings/${year}/game-${recordingId}/recording-${recordingId}.mp4`;

  await minio.putObject(
    config.storage.bucket,
    objectKey,
    createReadStream(input.outputPath),
    input.sizeBytes,
    {
      "Content-Type": "video/mp4",
    },
  );

  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const [lockedRows] = await connection.execute<RecordingRow[]>(
      `SELECT id, organization_id, owner_user_id, started_at, media_asset_id, status
         FROM recordings
         WHERE id = ?
         LIMIT 1
         FOR UPDATE`,
      [recordingId],
    );

    const locked = lockedRows[0];

    if (!locked) {
      throw new Error("Durable live recording disappeared during finalization.");
    }

    if (locked.media_asset_id != null) {
      await connection.commit();

      return {
        mediaAssetId: Number(locked.media_asset_id),
        objectKey,
      };
    }

    if (locked.status !== "PROCESSING" && locked.status !== "RECORDING") {
      throw new Error(`Recording ${recordingId} is not finalizable from status ${locked.status}.`);
    }

    const [asset] = await connection.execute<ResultSetHeader>(
      `INSERT INTO media_assets (
         organization_id,
         owner_user_id,
         media_kind,
         visibility,
         bucket,
         object_key,
         original_name,
         mime_type,
         size_bytes,
         captured_at,
         duration_ms,
         checksum_sha256
       )
       VALUES (?, ?, 'VIDEO', 'ORGANIZATION', ?, ?, ?, 'video/mp4', ?, ?, ?, ?)`,
      [
        organizationId,
        ownerUserId,
        config.storage.bucket,
        objectKey,
        `game-${recordingId}-recording.mp4`,
        input.sizeBytes,
        capturedAt,
        input.durationMs,
        input.checksumSha256,
      ],
    );

    const mediaAssetId = Number(asset.insertId);

    await connection.execute(
      `UPDATE recordings
         SET media_asset_id = ?,
             duration_ms = ?,
             status = 'READY'
         WHERE id = ?`,
      [mediaAssetId, input.durationMs, recordingId],
    );

    await connection.commit();

    return {
      mediaAssetId,
      objectKey,
    };
  } catch (error) {
    await connection.rollback();
    await minio.removeObject(config.storage.bucket, objectKey).catch(() => undefined);
    throw error;
  } finally {
    connection.release();
  }
}

export async function stopRecordingCaptureWithoutFinalize(gameId: string): Promise<void> {
  await stopCaptureProcess(gameId);
}

export async function stopAndFinalizeRecordingCapture(
  gameId: string,
): Promise<RecordingCaptureFinalizeResult> {
  const entry = await stopCaptureProcess(gameId);
  const recording = await latestDurableRecording(gameId);

  if (!recording) {
    if (entry) {
      await rm(entry.capturePath, { force: true }).catch(() => undefined);
    }

    return {
      finalized: false,
      recordingId: null,
      reason: "No durable LIVE recording exists for this game.",
    };
  }

  const recordingId = Number(recording.id);

  if (!entry) {
    const reason = "No recording capture runtime was available at normal stop.";
    await markLatestRecordingFailed(gameId, reason);

    return {
      finalized: false,
      recordingId,
      reason,
    };
  }

  let outputPath: string | null = null;

  try {
    const captureStat = await stat(entry.capturePath);

    if (captureStat.size <= 0) {
      throw new Error(
        entry.stderrTail.trim() || "Recording capture produced an empty source file.",
      );
    }

    outputPath = await finalizeCaptureFile(entry.capturePath);

    const outputStat = await stat(outputPath);
    const [durationMs, checksumSha256] = await Promise.all([
      probeDurationMs(outputPath),
      sha256File(outputPath),
    ]);

    const persisted = await persistFinalizedRecording({
      recording,
      outputPath,
      durationMs,
      checksumSha256,
      sizeBytes: outputStat.size,
    });

    await rm(entry.capturePath, { force: true });
    await rm(outputPath, { force: true });

    console.info(
      JSON.stringify({
        message: "Live recording capture finalized",
        gameId,
        recordingId,
        mediaAssetId: persisted.mediaAssetId,
        objectKey: persisted.objectKey,
        durationMs,
      }),
    );

    return {
      finalized: true,
      recordingId,
      mediaAssetId: persisted.mediaAssetId,
      objectKey: persisted.objectKey,
      durationMs,
    };
  } catch (error) {
    const reason = error instanceof Error ? error.message : String(error);

    await markLatestRecordingFailed(gameId, reason);

    return {
      finalized: false,
      recordingId,
      reason,
    };
  }
}

export type RecordingCaptureRecoverySummary = {
  recovered: number;
  cleaned: number;
  failed: number;
  skipped: number;
};

export async function recoverRecordingCapturesOnStartup(): Promise<RecordingCaptureRecoverySummary> {
  const summary: RecordingCaptureRecoverySummary = {
    recovered: 0,
    cleaned: 0,
    failed: 0,
    skipped: 0,
  };

  const directory = captureDirectory();
  let names: string[];

  try {
    names = await readdir(directory);
  } catch (error) {
    const code = error && typeof error === "object" && "code" in error ? String(error.code) : "";
    if (code === "ENOENT") {
      return summary;
    }
    throw error;
  }

  const orphanPattern = /^recording-(\d+)-game-(\d+)-(\d+)\.capture\.mkv$/;

  for (const name of names.sort()) {
    const match = orphanPattern.exec(name);

    if (!match) {
      continue;
    }

    const recordingId = Number(match[1]);
    const gameId = match[2] ?? "";
    const capturePath = path.join(directory, name);
    const recording = await durableRecordingById(recordingId, gameId);

    if (!recording) {
      summary.skipped += 1;
      continue;
    }

    if (recording.media_asset_id != null || ["READY", "ARCHIVED"].includes(recording.status)) {
      await rm(capturePath, { force: true }).catch(() => undefined);
      await rm(`${capturePath}.mp4`, { force: true }).catch(() => undefined);
      summary.cleaned += 1;
      continue;
    }

    if (!["RECORDING", "PROCESSING"].includes(recording.status)) {
      summary.skipped += 1;
      continue;
    }

    let outputPath: string | null = null;

    try {
      const source = await stat(capturePath);

      if (source.size <= 0) {
        throw new Error("Orphaned recording capture is empty.");
      }

      outputPath = await finalizeCaptureFile(capturePath);

      const output = await stat(outputPath);
      const [durationMs, checksumSha256] = await Promise.all([
        probeDurationMs(outputPath),
        sha256File(outputPath),
      ]);

      const persisted = await persistFinalizedRecording({
        recording,
        outputPath,
        durationMs,
        checksumSha256,
        sizeBytes: output.size,
      });

      await rm(capturePath, { force: true });
      await rm(outputPath, { force: true });

      summary.recovered += 1;

      console.info(
        JSON.stringify({
          message: "Recovered orphaned live recording capture after startup",
          gameId,
          recordingId,
          mediaAssetId: persisted.mediaAssetId,
          objectKey: persisted.objectKey,
          durationMs,
        }),
      );
    } catch (error) {
      summary.failed += 1;

      console.error(
        JSON.stringify({
          message: "Unable to recover orphaned live recording capture after startup",
          gameId,
          recordingId,
          capturePath,
          error: error instanceof Error ? error.message : String(error),
        }),
      );
    }
  }

  return summary;
}
