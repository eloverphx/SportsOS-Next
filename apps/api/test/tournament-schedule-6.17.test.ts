import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.17 incident drill-down", () => {
  it("links audit incidents to operational game surfaces", () => {
    expect(panel).toContain('import Link from "next/link"');
    expect(panel).toContain('`/games/${event.gameId}/control`');
    expect(panel).toContain('`/games/${event.gameId}/scoreboard`');
    expect(panel).toContain('`/games/${event.gameId}/overlay`');
  });

  it("uses stable per-incident action scopes", () => {
    expect(panel).toContain(
      'data-testid={`director-audit-actions-${event.id}`}',
    );
  });

  it("handles blocked create incidents that have no game id", () => {
    expect(panel).toContain(
      "This incident was recorded before a game record existed.",
    );
  });

  it("keeps incident history read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
