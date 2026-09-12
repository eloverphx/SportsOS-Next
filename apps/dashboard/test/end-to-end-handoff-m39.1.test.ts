import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function source(relativePath: string): string {
  return readFileSync(path.resolve(__dirname, relativePath), "utf8");
}

const scorekeeper = source("../app/games/[id]/control/page.tsx");
const coordinator = source("../../api/src/routes/broadcastSessionCoordinator.ts");
const streaming = source("../app/streaming/page.tsx");

describe("M39.1 game-to-broadcast acceptance handoff", () => {
  it("lets a stream manager prepare the current game from the scorekeeper console", () => {
    expect(scorekeeper).toContain("PERMISSIONS.STREAM_MANAGE");
    expect(scorekeeper).toContain("async function prepareBroadcast()");
    expect(scorekeeper).toContain("`/broadcast-coordinator/${game.id}/prepare`");
    expect(scorekeeper).toContain('method: "POST"');
    expect(scorekeeper).toContain("Prepare broadcast");
  });

  it("hands a successfully prepared game directly into broadcast focus mode", () => {
    expect(scorekeeper).toContain("router.push(`/broadcast/operations/${game.id}`)");
    expect(scorekeeper).toContain("useRouter()");
  });

  it("uses the existing guarded coordinator prepare endpoint", () => {
    expect(coordinator).toContain('app.post("/broadcast-coordinator/:gameId/prepare"');
    expect(coordinator).toContain("prepareBroadcastSession(gameId)");
    expect(coordinator).toContain("permission: PERMISSIONS.STREAM_MANAGE");
  });

  it("preserves the archive and authoritative-event highlight destination", () => {
    expect(streaming).toContain('api<RecordingsResponse>("/recordings?limit=100")');
    expect(streaming).toContain("event-anchors");
    expect(streaming).toContain("clip-jobs");
  });
});
