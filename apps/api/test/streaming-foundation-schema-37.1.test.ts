import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");

const migrations = readFileSync(resolve(apiRoot, "src/infrastructure/migrations.ts"), "utf8");

const streamingMigrations = readFileSync(
  resolve(apiRoot, "src/infrastructure/streaming-foundation-migrations.ts"),
  "utf8",
);

describe("Milestone 37.1 durable streaming foundation schema", () => {
  it("wires the streaming migration after authoritative game-event schema creation", () => {
    expect(migrations).toContain("runStreamingFoundationMigrations");

    const gameEventsIndex = migrations.indexOf("CREATE TABLE IF NOT EXISTS game_events");

    const streamingCallIndex = migrations.indexOf("await runStreamingFoundationMigrations()");

    expect(gameEventsIndex).toBeGreaterThanOrEqual(0);
    expect(streamingCallIndex).toBeGreaterThan(gameEventsIndex);
  });

  it("adds durable authenticated-session persistence without storing raw refresh tokens", () => {
    expect(streamingMigrations).toContain("CREATE TABLE IF NOT EXISTS auth_sessions");
    expect(streamingMigrations).toContain("refresh_token_hash CHAR(64)");
    expect(streamingMigrations).toContain("revoked_at DATETIME(3)");
    expect(streamingMigrations).not.toContain("refresh_token VARCHAR");
  });

  it("adds explicit media ownership and privacy metadata", () => {
    expect(streamingMigrations).toContain("owner_user_id");
    expect(streamingMigrations).toContain("ENUM('PRIVATE','ORGANIZATION','PUBLIC')");
    expect(streamingMigrations).toContain("checksum_sha256");
    expect(streamingMigrations).toContain("CREATE TABLE IF NOT EXISTS media_access_grants");
  });

  it("adds recordings and persistent stream-session metadata", () => {
    expect(streamingMigrations).toContain("CREATE TABLE IF NOT EXISTS recordings");
    expect(streamingMigrations).toContain("CREATE TABLE IF NOT EXISTS stream_sessions");
    expect(streamingMigrations).toContain("recording_id BIGINT UNSIGNED NULL");
    expect(streamingMigrations).toContain("'EMERGENCY_STOPPED'");
  });

  it("anchors video only to authoritative existing game events", () => {
    expect(streamingMigrations).toContain("CREATE TABLE IF NOT EXISTS recording_event_anchors");
    expect(streamingMigrations).toContain("FOREIGN KEY (game_event_id) REFERENCES game_events(id)");
    expect(streamingMigrations).toContain("anchor_source ENUM('SCOREKEEPER','SYSTEM')");
    const anchorSourceDefinition = streamingMigrations.match(/anchor_source\s+ENUM\(([^)]*)\)/);

    expect(anchorSourceDefinition?.[1]).toBe("'SCOREKEEPER','SYSTEM'");
  });
});
