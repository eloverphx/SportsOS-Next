import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");

function source(path: string): string {
  return readFileSync(resolve(apiRoot, path), "utf8");
}

const migrations = source("src/infrastructure/streaming-foundation-migrations.ts");
const jobs = source("src/modules/recording-clip-jobs/repository.ts");
const routes = source("src/routes/recordings.ts");

describe("Milestone 37.6 durable recording clip jobs", () => {
  it("persists an idempotent durable queue with media output linkage", () => {
    expect(migrations).toContain("CREATE TABLE IF NOT EXISTS recording_clip_jobs");
    expect(migrations).toContain("uq_recording_clip_job_window");
    expect(migrations).toContain("output_media_asset_id BIGINT UNSIGNED NULL");
    expect(migrations).toContain("fk_recording_clip_jobs_output_media");
    expect(jobs).toContain("ON DUPLICATE KEY UPDATE");
    expect(jobs).toContain("LAST_INSERT_ID(id)");
  });

  it("queues only from an existing recording event anchor", () => {
    expect(routes).toContain("findRecordingEventAnchor");
    expect(routes).toContain("anchor.voidedAt !== null");
    expect(routes).toContain("deriveEventClipWindow");
    expect(routes).toContain('selectionSource: "SCOREKEEPER_EVENT"');
  });

  it("does not accept client supplied clip timing or AI selection source", () => {
    const routeStart = routes.indexOf('"/recordings/:id/event-anchors/:eventId/clip-jobs"');
    const routeEnd = routes.indexOf('app.patch("/recordings/:id"', routeStart);

    expect(routeStart).toBeGreaterThanOrEqual(0);
    expect(routeEnd).toBeGreaterThan(routeStart);

    const routeBlock = routes.slice(routeStart, routeEnd);

    expect(routeBlock).not.toContain("request.body");
    expect(routeBlock).not.toContain("AI_SELECTION");
    expect(routeBlock).toContain("clipWindow.startMs");
    expect(routeBlock).toContain("clipWindow.endMs");
  });

  it("requires stream management to queue and stream read to list jobs", () => {
    expect(routes).toMatch(/\/recordings\/:id\/clip-jobs[\s\S]*?PERMISSIONS\.STREAM_READ/);
    expect(routes).toMatch(
      /\/recordings\/:id\/event-anchors\/:eventId\/clip-jobs[\s\S]*?PERMISSIONS\.STREAM_MANAGE/,
    );
  });

  it("reserves AI only as a future selector of authoritative anchored events", () => {
    expect(migrations).toContain("ENUM('SCOREKEEPER_EVENT','AI_SELECTION')");
    expect(migrations).not.toContain("AI_EVENT");
    expect(migrations).not.toContain("AI_ANCHOR");
  });
});
