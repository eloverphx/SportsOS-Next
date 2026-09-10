import { describe, expect, it } from "vitest";
import { buildFfmpegClipArgs } from "../src/modules/recording-clip-jobs/ffmpeg.js";

describe("Milestone 37.7 FFmpeg clip rendering", () => {
  it("builds a deterministic re-encode with faststart", () => {
    expect(
      buildFfmpegClipArgs({
        inputPath: "/tmp/source",
        outputPath: "/tmp/output.mp4",
        startMs: 22_000,
        endMs: 35_000,
      }),
    ).toEqual([
      "-hide_banner",
      "-loglevel",
      "error",
      "-y",
      "-ss",
      "22.000",
      "-i",
      "/tmp/source",
      "-t",
      "13.000",
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
      "/tmp/output.mp4",
    ]);
  });

  it("rejects invalid clip windows before spawning FFmpeg", () => {
    expect(() =>
      buildFfmpegClipArgs({
        inputPath: "/tmp/source",
        outputPath: "/tmp/output.mp4",
        startMs: 10_000,
        endMs: 10_000,
      }),
    ).toThrow(RangeError);
  });
});
