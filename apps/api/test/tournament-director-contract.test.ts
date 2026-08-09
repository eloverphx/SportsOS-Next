import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);
const shell = readFileSync(
  new URL("../../dashboard/components/AppShell.tsx", import.meta.url),
  "utf8",
);

describe("Tournament Director dashboard contract", () => {
  it("uses authoritative SportsOS operational feeds", () => {
    expect(page).toContain('api<{ games: Game[] }>("/games")');
    expect(page).toContain('api<{ devices: Device[] }>("/scoreboard-devices")');
    expect(page).toContain('api<EngineResponse>("/system/game-engine")');
    expect(page).toContain("`/games/${game.id}/penalties`");
  });

  it("refreshes from realtime game and device changes", () => {
    expect(page).toContain('"game:scored"');
    expect(page).toContain('"game:penalties-updated"');
    expect(page).toContain('"scoreboard-device:status"');
    expect(page).toContain('socket.on("connect"');
  });

  it("surfaces tournament operator attention and device health", () => {
    expect(page).toContain("OPERATOR_REQUIRED");
    expect(page).toContain("TRANSITION_PENDING");
    expect(page).toContain("actionRequired");
    expect(page).toContain("Assigned devices offline");
    expect(page).toContain("Active penalties");
  });

  it("links directly into the game-day operating surfaces", () => {
    expect(page).toContain('href={`/games/${game.id}/control`}');
    expect(page).toContain('href={`/games/${game.id}/scoreboard`}');
    expect(page).toContain('href={`/games/${game.id}/overlay`}');
    expect(page).toContain("Engine Health");
  });

  it("is reachable from SportsOS navigation", () => {
    expect(shell).toContain('label: "Tournament Director"');
    expect(shell).toContain('href: "/tournament-director"');
    expect(shell).toContain("permission: PERMISSIONS.GAME_READ");
  });
});
