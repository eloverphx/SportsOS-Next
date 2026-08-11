import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const timeline = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleTimeline.tsx",
    import.meta.url,
  ),
  "utf8",
);

const css = readFileSync(
  new URL(
    "../../dashboard/components/tournament/tournament-schedule-timeline.css",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.20 cross-day incident navigation", () => {
  it("parses only stable timeline game hashes", () => {
    expect(timeline).toContain("function timelineGameIdFromHash(");
    expect(timeline).toContain(
      "/^#director-timeline-game-(\\d+)$/",
    );
  });

  it("switches the selected tournament day to the target game's current day", () => {
    expect(timeline).toContain('window.addEventListener("hashchange"');
    expect(timeline).toContain("activeGames.find((entry) => entry.id === gameId)");
    expect(timeline).toContain("const targetDay = dayKey(game.scheduledStart)");
    expect(timeline).toContain("setSelectedDay(targetDay)");
  });

  it("scrolls to the target only after its day is rendered", () => {
    expect(timeline).toContain("window.requestAnimationFrame");
    expect(timeline).toContain(
      "`director-timeline-game-${targetGameId}`",
    );
    expect(timeline).toContain("scrollIntoView({");
    expect(timeline).toContain('block: "center"');
  });

  it("visually identifies the audit target", () => {
    expect(timeline).toContain(
      'targetGameId === game.id ? "audit-target" : ""',
    );
    expect(css).toContain(".tournamentTimelineGame.audit-target");
    expect(css).toContain("@media (prefers-reduced-motion: reduce)");
  });

  it("remains read-only", () => {
    expect(timeline).not.toContain('method: "POST"');
    expect(timeline).not.toContain('method: "PUT"');
    expect(timeline).not.toContain('method: "DELETE"');
  });
});
