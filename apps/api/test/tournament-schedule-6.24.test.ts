import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.24 server-wired audit filters and paging", () => {
  it("supports system-admin organization filtering with scoped-role protection", () => {
    expect(routes).toContain("organizationId?: string");
    expect(routes).toContain("const requestedOrganizationId");
    expect(routes).toContain('code: "AUDIT_ORGANIZATION_FORBIDDEN"');
    expect(routes).toContain(
      "requestedOrganizationId !== identity.organizationId",
    );
  });

  it("builds server queries from active audit filters", () => {
    expect(panel).toContain("new URLSearchParams");
    expect(panel).toContain('params.set("decision", decision)');
    expect(panel).toContain('params.set("gameId", debouncedGameId)');
    expect(panel).toContain('params.set("venue", rink)');
    expect(panel).toContain('params.set("actorUserId"');
    expect(panel).toContain('params.set("organizationId", organizationId)');
  });

  it("avoids coupling the loader directly to the events array", () => {
    expect(panel).toContain("const selectedActorUserId = useMemo(");
    expect(panel).toContain("selectedActorUserId,");
    expect(panel).not.toContain("    events,\n    organizationId,");
  });

  it("debounces game-id filtering and resets pagination", () => {
    expect(panel).toContain("setDebouncedGameId(gameId.trim())");
    expect(panel).toContain("300");
    expect(panel).toContain("setPageOffset(0)");
  });

  it("renders bounded previous and next paging", () => {
    expect(panel).toContain("const AUDIT_PAGE_SIZE = 25");
    expect(panel).toContain('data-testid="director-audit-pagination"');
    expect(panel).toContain("Previous");
    expect(panel).toContain("Next");
    expect(panel).toContain("Math.ceil(serverTotal / AUDIT_PAGE_SIZE)");
  });

  it("uses the server total as authoritative", () => {
    expect(panel).toContain("setServerTotal(response.total)");
    expect(panel).toContain("total: serverTotal");
  });

  it("remains read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
