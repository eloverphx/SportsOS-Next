import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pageFile = path.resolve(__dirname, "../app/streaming/page.tsx");
const source = readFileSync(pageFile, "utf8");

describe("M37.12 streaming highlight operations", () => {
  it("loads authoritative anchors and durable clip jobs", () => {
    expect(source).toContain("`/recordings/${recordingId}/event-anchors`");
    expect(source).toContain("`/recordings/${recordingId}/clip-jobs`");
    expect(source).toContain("anchor.anchorSource");
    expect(source).toContain("anchor.suggestedClipWindow");
  });

  it("queues only server-derived anchor clip jobs", () => {
    expect(source).toContain(
      "`/recordings/${operationsRecordingId}/event-anchors/${anchor.gameEventId}/clip-jobs`",
    );

    const queueClipStart = source.indexOf("async function queueClip");
    const openClipPlaybackStart = source.indexOf("async function openClipPlayback");
    const queueClipSource = source.slice(queueClipStart, openClipPlaybackStart);

    expect(queueClipStart).toBeGreaterThan(-1);
    expect(openClipPlaybackStart).toBeGreaterThan(queueClipStart);
    expect(queueClipSource).toContain('{ method: "POST" }');
    expect(queueClipSource).not.toContain("startMs:");
    expect(queueClipSource).not.toContain("endMs:");
  });

  it("gates creation on STREAM_MANAGE", () => {
    expect(source).toContain("userHasPermission(getStoredUser(), PERMISSIONS.STREAM_MANAGE)");
    expect(source).toContain("canManageStreaming && anchor.eligibleForHighlights");
  });

  it("polls jobs and surfaces worker state", () => {
    expect(source).toContain("5_000");
    expect(source).toContain("job.errorMessage");
    for (const status of ["PENDING", "PROCESSING", "READY", "FAILED", "CANCELLED"]) {
      expect(source).toContain(`"${status}"`);
    }
  });

  it("reuses authenticated playback for READY clips", () => {
    expect(source).toContain("job.outputMediaAssetId");
    expect(source).toContain("/playback-session");
    expect(source).toContain('credentials: "include"');
    expect(source).toContain("<video");
    expect(source).not.toContain("token=");
    expect(source).not.toContain("sportsos_token");
  });
});
