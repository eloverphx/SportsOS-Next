import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const audit = readFileSync(
  new URL("../src/modules/games/schedule-audit.ts", import.meta.url),
  "utf8",
);

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.18 incident evidence detail", () => {
  it("normalizes stored conflict evidence into the audit read model", () => {
    expect(audit).toContain("export type ScheduleAuditConflict");
    expect(audit).toContain("function normalizeConflicts(");
    expect(audit).toContain("details.conflicts");
    expect(audit).toContain("details.scheduleConflicts");
    expect(audit).toContain("conflicts: normalizeConflicts(details)");
  });

  it("preserves conflict identifiers and messages", () => {
    expect(audit).toContain("code:");
    expect(audit).toContain("severity:");
    expect(audit).toContain("gameId:");
    expect(audit).toContain("relatedGameId:");
    expect(audit).toContain("message:");
  });

  it("renders expandable evidence for incidents", () => {
    expect(panel).toContain('className="scheduleAuditEvidence"');
    expect(panel).toContain("View conflict evidence");
    expect(panel).toContain("event.conflicts.map");
    expect(panel).toContain("conflict.code.replaceAll");
    expect(panel).toContain("conflict.message");
    expect(panel).toContain("Related game #");
  });

  it("keeps incident evidence read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
