import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.16 incident filtering", () => {
  it("supports the required incident filters", () => {
    expect(panel).toContain("All decisions");
    expect(panel).toContain("Blocked only");
    expect(panel).toContain("Overridden only");
    expect(panel).toContain("Game ID");
    expect(panel).toContain("All rinks");
    expect(panel).toContain("All actors");
    expect(panel).toContain("All organizations");
  });

  it("derives filter options from authoritative audit results", () => {
    expect(panel).toContain("const rinkOptions = useMemo");
    expect(panel).toContain("const actorOptions = useMemo");
    expect(panel).toContain("const organizationOptions = useMemo");
  });

  it("filters read-only audit rows through server query parameters", () => {
    expect(panel).toContain("new URLSearchParams");
    expect(panel).toContain('params.set("decision", decision)');
    expect(panel).toContain('params.set("gameId", debouncedGameId)');
    expect(panel).toContain('params.set("venue", rink)');
    expect(panel).toContain('params.set("actorUserId"');
    expect(panel).toContain('params.set("organizationId", organizationId)');
    expect(panel).toContain("const filteredEvents = events");
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });

  it("provides stable test scopes for filters and results", () => {
    expect(panel).toContain('data-testid="director-audit-filters"');
    expect(panel).toContain('data-testid="director-audit-events"');
  });

  it("can clear every active filter in one action", () => {
    expect(panel).toContain("Clear filters");
    expect(panel).toContain('setDecision("ALL")');
    expect(panel).toContain('setGameId("")');
    expect(panel).toContain('setRink("ALL")');
    expect(panel).toContain('setActor("ALL")');
    expect(panel).toContain('setOrganizationId("ALL")');
  });
});
