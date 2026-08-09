import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const ops = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentDayOperations.tsx",
    import.meta.url,
  ),
  "utf8",
);

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament day 6.8 operations contract", () => {
  it("mounts the director attention queue in Tournament Director", () => {
    expect(page).toContain("TournamentDayOperations");
    expect(page).toContain("games={games}");
    expect(page).toContain("devices={devices}");
    expect(page).toContain("engineGames={engine?.games ?? []}");
  });

  it("surfaces late and starting-soon scheduled games", () => {
    expect(ops).toContain("delta < -5");
    expect(ops).toContain("delta <= 15");
    expect(ops).toContain("is late");
    expect(ops).toContain("starts soon");
  });

  it("surfaces offline assigned scoreboards", () => {
    expect(ops).toContain('device.status === "OFFLINE"');
    expect(ops).toContain("Scoreboard offline for game");
  });

  it("surfaces authoritative engine attention states", () => {
    expect(ops).toContain('engine.state === "OPERATOR_REQUIRED"');
    expect(ops).toContain('engine.state === "TRANSITION_PENDING"');
    expect(ops).toContain('engine.state === "WARNING"');
  });

  it("detects tight rink turnover gaps", () => {
    expect(ops).toContain("gapMinutes >= 0 && gapMinutes <= 20");
    expect(ops).toContain("turnover is tight");
  });

  it("prioritizes critical items and links to operator surfaces", () => {
    expect(ops).toContain("right.priority - left.priority");
    expect(ops).toContain('href={`/games/${issue.gameId}/control`}');
    expect(ops).toContain('href={`/games/${issue.gameId}/scoreboard`}');
  });

  it("remains read-only", () => {
    expect(ops).not.toContain('method: "PUT"');
    expect(ops).not.toContain('method: "POST"');
    expect(ops).not.toContain('method: "DELETE"');
  });
});
