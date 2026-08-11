import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const auditPanel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

const timeline = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleTimeline.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.19 incident-to-schedule correlation", () => {
  it("gives every timeline game Link a stable game anchor", () => {
    expect(timeline).toContain(
      'id={`director-timeline-game-${game.id}`}',
    );
    expect(timeline).toContain("data-game-id={game.id}");
    expect(timeline).toContain('href={`/games/${game.id}/control`}');
  });

  it("links incidents back to the current schedule row", () => {
    expect(auditPanel).toContain(
      '`#director-timeline-game-${event.gameId}`',
    );
    expect(auditPanel).toContain("View in schedule timeline");
  });

  it("links recorded conflict participants to their timeline rows", () => {
    expect(auditPanel).toContain(
      '`#director-timeline-game-${conflict.gameId}`',
    );
    expect(auditPanel).toContain(
      '`#director-timeline-game-${conflict.relatedGameId}`',
    );
    expect(auditPanel).toContain("View game in timeline");
    expect(auditPanel).toContain("View related game in timeline");
  });

  it("keeps correlation navigation read-only", () => {
    expect(auditPanel).not.toContain('method: "POST"');
    expect(auditPanel).not.toContain('method: "PUT"');
    expect(auditPanel).not.toContain('method: "DELETE"');
  });
});
