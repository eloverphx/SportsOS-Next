import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.22 incident summary metrics", () => {
  it("derives summary metrics from audit events and current conflict state", () => {
    expect(panel).toContain("const incidentSummary = useMemo(");
    expect(panel).toContain("currentIncidentStatus(event, games, currentConflicts)");
    expect(panel).toContain('status === "CURRENT_CONFLICT"');
    expect(panel).toContain('status === "RESOLVED"');
    expect(panel).toContain('eventKind(event.action) === "OVERRIDDEN"');
  });

  it("shows total, active, resolved, override, and blocked counts", () => {
    expect(panel).toContain("Total decisions");
    expect(panel).toContain("Still active");
    expect(panel).toContain("Resolved");
    expect(panel).toContain("Overrides");
    expect(panel).toContain("Blocked");
  });

  it("provides a stable summary metrics test scope", () => {
    expect(panel).toContain('data-testid="director-audit-summary-metrics"');
  });

  it("remains read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
