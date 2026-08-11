import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

const page = readFileSync(
  new URL(
    "../../dashboard/app/tournament-director/page.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.21 current conflict resolution status", () => {
  it("passes current schedule games into the audit panel", () => {
    expect(page).toContain("<TournamentScheduleAudit games={games} />");
    expect(panel).toContain(
      "export function TournamentScheduleAudit({ games }: Props)",
    );
  });

  it("uses the shared current schedule conflict detector", () => {
    expect(panel).toContain("detectScheduleConflicts");
    expect(panel).toContain("const currentConflicts = useMemo(");
    expect(panel).toContain("detectScheduleConflicts(games)");
  });

  it("distinguishes current, resolved, never-created, and removed incidents", () => {
    expect(panel).toContain('"CURRENT_CONFLICT"');
    expect(panel).toContain('"RESOLVED"');
    expect(panel).toContain('"GAME_NOT_CREATED"');
    expect(panel).toContain('"GAME_NOT_FOUND"');
    expect(panel).toContain("Conflict still present");
    expect(panel).toContain("Conflict resolved");
    expect(panel).toContain("No game record created");
    expect(panel).toContain("Game no longer present");
  });

  it("renders a stable current-status indicator per audit event", () => {
    expect(panel).toContain("scheduleAuditCurrentStatus");
    expect(panel).toContain(
      'data-testid={`director-audit-current-status-${event.id}`}',
    );
  });

  it("remains read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
