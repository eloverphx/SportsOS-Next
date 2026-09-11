import { createHash } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { mkdtemp, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pipeline } from "node:stream/promises";
import { setTimeout as sleep } from "node:timers/promises";
import { config } from "@sportsos/config";
import { minio } from "../infrastructure/minio.js";
import { runFfmpegClip } from "../modules/recording-clip-jobs/ffmpeg.js";
import {
  claimNextRecordingClipJob,
  completeRecordingClipJob,
  markRecordingClipJobAttemptFailed,
} from "../modules/recording-clip-jobs/repository.js";

const IDLE_POLL_MS = 2_000;

function errorMessage(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 1000);
}

async function sha256File(path: string): Promise<string> {
  const hash = createHash("sha256");
  const stream = createReadStream(path);

  for await (const chunk of stream) {
    hash.update(chunk);
  }

  return hash.digest("hex");
}

export async function processNextRecordingClipJob(): Promise<boolean> {
  const job = await claimNextRecordingClipJob();

  if (!job) {
    return false;
  }

  const workDir = await mkdtemp(join(tmpdir(), `sportsos-clip-${job.id}-`));

  const sourcePath = join(workDir, "source-video");
  const outputPath = join(workDir, "clip.mp4");

  const year = new Date().getUTCFullYear();
  const objectKey = `clips/${year}/job-${job.id}-attempt-${job.attemptCount}.mp4`;

  try {
    const source = await minio.getObject(job.sourceBucket, job.sourceObjectKey);

    await pipeline(source, createWriteStream(sourcePath));

    await runFfmpegClip({
      inputPath: sourcePath,
      outputPath,
      startMs: job.startMs,
      endMs: job.endMs,
    });

    const outputStat = await stat(outputPath);

    if (outputStat.size <= 0) {
      throw new Error("FFmpeg produced an empty clip");
    }

    const checksumSha256 = await sha256File(outputPath);

    await minio.putObject(
      config.storage.bucket,
      objectKey,
      createReadStream(outputPath),
      outputStat.size,
      {
        "Content-Type": "video/mp4",
      },
    );

    try {
      const outputMediaAssetId = await completeRecordingClipJob({
        jobId: job.id,
        attemptCount: job.attemptCount,
        bucket: config.storage.bucket,
        objectKey,
        sizeBytes: outputStat.size,
        checksumSha256,
      });

      console.info(
        JSON.stringify({
          message: "Recording clip job ready",
          jobId: job.id,
          outputMediaAssetId,
          objectKey,
        }),
      );
    } catch (error) {
      await minio.removeObject(config.storage.bucket, objectKey).catch(() => undefined);

      throw error;
    }

    return true;
  } catch (error) {
    await markRecordingClipJobAttemptFailed(job.id, job.attemptCount, errorMessage(error));

    console.error(
      JSON.stringify({
        message: "Recording clip job attempt failed",
        jobId: job.id,
        attemptCount: job.attemptCount,
        error: errorMessage(error),
      }),
    );

    return true;
  } finally {
    await rm(workDir, {
      recursive: true,
      force: true,
    });
  }
}

export async function runRecordingClipWorker(signal: AbortSignal): Promise<void> {
  console.info(
    JSON.stringify({
      message: "Recording clip worker started",
    }),
  );

  while (!signal.aborted) {
    try {
      const processed = await processNextRecordingClipJob();

      if (!processed) {
        await sleep(IDLE_POLL_MS, undefined, {
          signal,
        });
      }
    } catch (error) {
      console.error(
        JSON.stringify({
          message: "Recording clip worker loop error",
          error: errorMessage(error),
        }),
      );

      try {
        await sleep(IDLE_POLL_MS, undefined, {
          signal,
        });
      } catch {
        // Abort during shutdown is expected.
      }
    }
  }

  console.info(
    JSON.stringify({
      message: "Recording clip worker stopped",
    }),
  );
}
