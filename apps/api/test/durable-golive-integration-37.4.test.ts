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
const bridge = source("src/services/durableGoLiveBridge.ts");
const routes = source("src/routes/goLiveSessions.ts");
const recordingPolicy = source("src/modules/recordings/access-policy.ts");

describe("Milestone 37.4 durable go-live integration contract", () => {
  it("supports organization/system-owned live rows without inventing a user", () => {
    expect(migrations).toContain("owner_user_id BIGINT UNSIGNED NULL");
    expect(migrations).toContain("created_by_user_id BIGINT UNSIGNED NULL");
    expect(migrations).toContain('columnIsNullable("recordings", "owner_user_id")');
    expect(migrations).toContain('columnIsNullable("stream_sessions", "created_by_user_id")');
    expect(recordingPolicy).toContain("readonly ownerUserId: number | null");
  });

  it("writes stream-session lifecycle and live recording metadata transactionally", () => {
    expect(bridge).toContain("await connection.beginTransaction()");
    expect(bridge).toContain("INSERT INTO stream_sessions");
    expect(bridge).toContain("INSERT INTO recordings");
    expect(bridge).toContain("UPDATE stream_sessions");
    expect(bridge).toContain("UPDATE recordings");
    expect(bridge).toContain("await connection.commit()");
  });

  it("mirrors all critical state-changing go-live paths", () => {
    expect(routes).toContain("persistDurableSession(request, gameId, session)");
    expect(routes).toContain("persistDurableSession(request, gameId, startingSession)");
    expect(routes).toContain("persistDurableSession(request, gameId, stoppingSession)");
    expect(routes).toContain("persistDurableReset(request, gameId)");
  });

  it("preserves the existing file-backed coordinator instead of replacing its state machine", () => {
    expect(routes).toContain("armGoLiveSession(gameId)");
    expect(routes).toContain("markGoLiveStarting(gameId)");
    expect(routes).toContain("markGoLiveLive(gameId)");
    expect(routes).toContain("markGoLiveDegraded(gameId");
    expect(routes).toContain("completeGoLiveSession(gameId)");
    expect(routes).toContain("resetGoLiveSession(gameId)");
  });

  it("treats durable persistence failures as observable errors without stopping the live coordinator", () => {
    expect(routes).toContain('"Durable go-live synchronization failed"');
    expect(routes).toContain("request.log.error");
  });
});
