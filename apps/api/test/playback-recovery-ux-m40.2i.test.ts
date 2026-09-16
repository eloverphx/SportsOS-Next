import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const mediaRoute = readFileSync(new URL("../src/routes/media.ts", import.meta.url), "utf8");

const recordingCaptureRuntime = readFileSync(
  new URL("../src/services/recordingCaptureRuntime.ts", import.meta.url),
  "utf8",
);

const dashboardApi = readFileSync(new URL("../../dashboard/lib/api.ts", import.meta.url), "utf8");

const dashboardCsp = readFileSync(
  new URL("../../dashboard/lib/contentSecurityPolicy.ts", import.meta.url),
  "utf8",
);

const streamingPage = readFileSync(
  new URL("../../dashboard/app/streaming/page.tsx", import.meta.url),
  "utf8",
);

describe("M40.2i protected archive playback", () => {
  it("permits the authenticated playback response to be embedded cross-origin", () => {
    expect(mediaRoute).toContain('reply.header("Cross-Origin-Resource-Policy", "cross-origin")');
  });

  it("does not reintroduce the hard-coded ticket-org media-org equality gate", () => {
    expect(mediaRoute).not.toContain("asset.organizationId !== ticket.organizationId");

    expect(mediaRoute).toContain("canViewMedia(identity, asset)");
  });

  it("keeps credentials enabled for dashboard API requests", () => {
    expect(dashboardApi).toContain('credentials: "include"');
  });

  it("allows the API origin as a dashboard media source", () => {
    expect(dashboardCsp).toContain("media-src 'self' blob:");
    expect(dashboardCsp).toContain("https://api.crashthenet.online");
  });
});

describe("M40.2i recording finalization validation", () => {
  it("validates finalized H.264 metadata before publishing the archive", () => {
    expect(recordingCaptureRuntime).toContain("async function validateFinalizedRecording");

    expect(recordingCaptureRuntime).toContain("stream=codec_name,profile,pix_fmt,level");

    expect(recordingCaptureRuntime).toContain("Finalized recording has an unknown H.264 profile.");

    expect(recordingCaptureRuntime).toContain("Finalized recording has an unknown pixel format.");

    expect(recordingCaptureRuntime).toContain("Finalized recording has an invalid H.264 level.");
  });

  it("falls back from an invalid remux to a transcode and validates again", () => {
    expect(recordingCaptureRuntime).toContain("buildRecordingRemuxArgs(capturePath, outputPath)");

    expect(recordingCaptureRuntime).toContain(
      "buildRecordingTranscodeArgs(capturePath, outputPath)",
    );

    expect(recordingCaptureRuntime).toContain("await rm(outputPath, { force: true })");

    const validationCalls = recordingCaptureRuntime.match(
      /validateFinalizedRecording\(outputPath\)/g,
    );

    expect(validationCalls?.length).toBeGreaterThanOrEqual(2);
  });
});

describe("M40.2i tablet playback UX", () => {
  it("keeps the archive player responsive on tablet-sized screens", () => {
    expect(streamingPage).toContain("max-w-[900px]");
    expect(streamingPage).toContain("max-h-[68dvh]");
    expect(streamingPage).toContain("object-contain");
  });

  it("moves playback into view and attempts immediate playback", () => {
    expect(streamingPage).toContain("scrollIntoView");
    expect(streamingPage).toContain('behavior: "smooth"');
    expect(streamingPage).toContain("video.play()");
  });

  it("retains fullscreen support including Safari fallback", () => {
    expect(streamingPage).toContain("requestFullscreen");
    expect(streamingPage).toContain("webkitEnterFullscreen");
  });
});
