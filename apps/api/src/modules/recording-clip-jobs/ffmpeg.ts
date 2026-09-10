import { spawn } from "node:child_process";
import { assertValidClipWindow } from "./policy.js";

function seconds(ms: number): string {
  return (ms / 1000).toFixed(3);
}

export function buildFfmpegClipArgs(input: {
  readonly inputPath: string;
  readonly outputPath: string;
  readonly startMs: number;
  readonly endMs: number;
}): string[] {
  assertValidClipWindow(input.startMs, input.endMs);

  return [
    "-hide_banner",
    "-loglevel",
    "error",
    "-y",
    "-ss",
    seconds(input.startMs),
    "-i",
    input.inputPath,
    "-t",
    seconds(input.endMs - input.startMs),
    "-map",
    "0:v:0?",
    "-map",
    "0:a:0?",
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-crf",
    "23",
    "-c:a",
    "aac",
    "-b:a",
    "160k",
    "-movflags",
    "+faststart",
    input.outputPath,
  ];
}

export async function runFfmpegClip(input: {
  readonly inputPath: string;
  readonly outputPath: string;
  readonly startMs: number;
  readonly endMs: number;
  readonly ffmpegPath?: string;
}): Promise<void> {
  const args = buildFfmpegClipArgs(input);
  const ffmpegPath = input.ffmpegPath || process.env.FFMPEG_PATH || "ffmpeg";

  await new Promise<void>((resolve, reject) => {
    const child = spawn(ffmpegPath, args, {
      stdio: ["ignore", "ignore", "pipe"],
    });

    let stderr = "";

    child.stderr.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk.toString("utf8")).slice(-16_000);
    });

    child.once("error", reject);

    child.once("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(
        new Error(`FFmpeg exited with code ${code ?? "unknown"}${stderr ? `: ${stderr}` : ""}`),
      );
    });
  });
}
