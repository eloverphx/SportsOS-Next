import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const editor = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleEditor.tsx",
    import.meta.url,
  ),
  "utf8",
);

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament scheduling 6.4 contract", () => {
  it("limits interactive moves to scheduled games", () => {
    expect(editor).toContain('game.status === "SCHEDULED"');
    expect(editor).toContain(
      "Only scheduled games can be moved from Tournament Director.",
    );
  });

  it("previews conflicts before saving through the authoritative server", () => {
    expect(editor).toContain("`/games/${draft.gameId}/schedule-preview`");
    expect(editor).toContain('method: "POST"');
    expect(editor).toContain("Hard conflicts");
    expect(editor).toContain("Server validation found no schedule conflicts.");
  });

  it("blocks hard conflicts until explicitly overridden", () => {
    expect(editor).toContain("preview.hardConflict && !overrideHardConflicts");
    expect(editor).toContain("want to override the block");
    expect(editor).toContain("window.confirm");
    expect(editor).toContain("scheduleConflictOverride: overrideHardConflicts");
  });

  it("fetches the authoritative full game before issuing PUT", () => {
    expect(editor).toContain('api<{ game: FullGame }>(`/games/${draft.gameId}`)');
    expect(editor).toContain('method: "PUT"');
    expect(editor).toContain("organizationId: game.organizationId");
    expect(editor).toContain("seasonId: game.seasonId");
    expect(editor).toContain(
      "regulationPeriodLengthMs: game.regulationPeriodLengthMs",
    );
    expect(editor).toContain("intermissionLengthMs: game.intermissionLengthMs");
    expect(editor).toContain("overtimeLengthMs: game.overtimeLengthMs");
  });

  it("requires game management permission", () => {
    expect(editor).toContain("PERMISSIONS.GAME_MANAGE");
    expect(editor).toContain("userHasPermission");
  });

  it("is mounted in Tournament Director and refreshes after save", () => {
    expect(page).toContain("TournamentScheduleEditor");
    expect(page).toContain(
      "<TournamentScheduleEditor games={games} onSaved={load} />",
    );
  });
});
