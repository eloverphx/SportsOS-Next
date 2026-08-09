import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const timeline = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleTimeline.tsx",
    import.meta.url,
  ),
  "utf8",
);

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament schedule 6.7 timeline contract", () => {
  it("mounts a tournament schedule timeline in Tournament Director", () => {
    expect(page).toContain("TournamentScheduleTimeline");
    expect(page).toContain("<TournamentScheduleTimeline games={games} />");
  });

  it("provides a day selector and rink grouping", () => {
    expect(timeline).toContain("Tournament day");
    expect(timeline).toContain('game.venue?.trim() || "Rink not assigned"');
    expect(timeline).toContain("Array.from(map.entries())");
  });

  it("renders a 30-minute horizontal time scale", () => {
    expect(timeline).toContain("MINUTES_PER_TICK = 30");
    expect(timeline).toContain("PIXELS_PER_HOUR = 180");
    expect(timeline).toContain("tournamentTimelineTick");
  });

  it("uses configured game duration with a safe fallback", () => {
    expect(timeline).toContain("game.regulationPeriods");
    expect(timeline).toContain("game.regulationPeriodLengthMs");
    expect(timeline).toContain("game.intermissionLengthMs");
    expect(timeline).toContain("FALLBACK_GAME_DURATION_MS");
  });

  it("shows conflict severity without controlling schedule writes", () => {
    expect(timeline).toContain("detectScheduleConflicts(dayGames)");
    expect(timeline).toContain('severity ? `conflict-${severity.toLowerCase()}` : ""');
    expect(timeline).toContain('severity === "ERROR" ? "CONFLICT" : "WARNING"');
    expect(timeline).not.toContain('method: "PUT"');
  });

  it("links game blocks directly to Scorekeeper", () => {
    expect(timeline).toContain('href={`/games/${game.id}/control`}');
  });

  it("shows a live now marker when the selected day is today", () => {
    expect(timeline).toContain("selectedDay === todayKey");
    expect(timeline).toContain("tournamentTimelineNow");
    expect(timeline).toContain("Current time");
  });
});
