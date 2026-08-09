import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const focus = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentFocusPanel.tsx",
    import.meta.url,
  ),
  "utf8",
);

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament focus 6.9 contract", () => {
  it("mounts focus mode in Tournament Director", () => {
    expect(page).toContain("TournamentFocusPanel");
    expect(page).toContain("<TournamentFocusPanel games={games} />");
  });

  it("filters by rink, organization, team, and urgency", () => {
    expect(focus).toContain("All rinks");
    expect(focus).toContain("All organizations");
    expect(focus).toContain("All teams");
    expect(focus).toContain("All urgency");
  });

  it("uses the established late and starting-soon thresholds", () => {
    expect(focus).toContain("deltaMs < -5 * 60_000");
    expect(focus).toContain("deltaMs <= 15 * 60_000");
  });

  it("prioritizes late, live, then starting-soon games", () => {
    expect(focus).toContain("LATE: 0");
    expect(focus).toContain("LIVE: 1");
    expect(focus).toContain("STARTING_SOON: 2");
    expect(focus).toContain("NORMAL: 3");
  });

  it("excludes completed and canceled games from focus mode", () => {
    expect(focus).toContain('game.status !== "FINAL"');
    expect(focus).toContain('game.status !== "CANCELED"');
  });

  it("links directly to all main operator surfaces", () => {
    expect(focus).toContain('href={`/games/${game.id}/control`}');
    expect(focus).toContain('href={`/games/${game.id}/scoreboard`}');
    expect(focus).toContain('href={`/games/${game.id}/overlay`}');
  });

  it("remains read-only", () => {
    expect(focus).not.toContain('method: "PUT"');
    expect(focus).not.toContain('method: "POST"');
    expect(focus).not.toContain('method: "DELETE"');
  });
});
