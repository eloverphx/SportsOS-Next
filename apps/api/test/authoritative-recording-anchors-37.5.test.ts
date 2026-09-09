import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");

function source(path: string): string {
  return readFileSync(resolve(apiRoot, path), "utf8");
}

const eventRepository = source("src/modules/game-events/repository.ts");
const anchorRepository = source("src/modules/recording-event-anchors/repository.ts");
const recordingRoutes = source("src/routes/recordings.ts");
const migrations = source("src/infrastructure/streaming-foundation-migrations.ts");

describe("Milestone 37.5 authoritative recording anchors", () => {
  it("creates an anchor inside the authoritative scorekeeper event transaction", () => {
    const begin = eventRepository.indexOf("await connection.beginTransaction()");
    const anchor = eventRepository.indexOf("await createAuthoritativeRecordingAnchor");
    const commit = eventRepository.indexOf("await connection.commit();", anchor);

    expect(begin).toBeGreaterThanOrEqual(0);
    expect(anchor).toBeGreaterThan(begin);
    expect(commit).toBeGreaterThan(anchor);
  });

  it("derives offset only from the scorekeeper event timestamp and active recording start", () => {
    expect(anchorRepository).toContain("eventCreatedAt - recordingStartedAt");
    expect(anchorRepository).toContain("status = 'RECORDING'");
    expect(anchorRepository).toContain("VALUES (?, ?, ?, 'SCOREKEEPER')");
  });

  it("does not expose a route for clients or AI to create or move event anchors", () => {
    expect(recordingRoutes).toMatch(/app\.get\(\s*["']\/recordings\/:id\/event-anchors["']/);

    expect(recordingRoutes).not.toContain('app.post("/recordings/:id/event-anchors"');

    expect(recordingRoutes).not.toContain('app.patch("/recordings/:id/event-anchors"');

    expect(anchorRepository).not.toMatch(/\bAI\b/);
  });

  it("retains voided-event anchors for audit while marking them ineligible for highlights", () => {
    expect(anchorRepository).toContain("ge.voided_at");
    expect(recordingRoutes).toContain("anchor.voidedAt === null");
    expect(eventRepository).not.toContain("DELETE FROM recording_event_anchors");
  });

  it("retains the migration-level ban on AI-authored anchor sources", () => {
    const sourceDefinition = migrations.match(/anchor_source\s+ENUM\(([^)]*)\)/);

    expect(sourceDefinition?.[1]).toBe("'SCOREKEEPER','SYSTEM'");
  });
});
