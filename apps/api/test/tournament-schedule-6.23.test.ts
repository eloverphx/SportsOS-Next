import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const audit = readFileSync(
  new URL("../src/modules/games/schedule-audit.ts", import.meta.url),
  "utf8",
);

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

describe("Tournament scheduling 6.23 server-side audit filtering and pagination", () => {
  it("keeps the proven legacy audit reader intact", () => {
    expect(audit).toContain(
      "export async function listRecentScheduleAuditEvents(",
    );
  });

  it("adds a bounded paginated audit query", () => {
    expect(audit).toContain("export type ScheduleAuditQuery");
    expect(audit).toContain("export type ScheduleAuditPage");
    expect(audit).toContain("boundedScheduleAuditInteger(");
    expect(audit).toContain("LIMIT ?");
    expect(audit).toContain("OFFSET ?");
  });

  it("filters organization, game, venue, actor, and decision in SQL", () => {
    expect(audit).toContain("$.organizationId");
    expect(audit).toContain("$.gameId");
    expect(audit).toContain("$.venue");
    expect(audit).toContain("$.requestedVenue");
    expect(audit).toContain("a.user_id = ?");
    expect(audit).toContain('decision === "BLOCKED"');
    expect(audit).toContain('decision === "OVERRIDDEN"');
  });

  it("returns page metadata", () => {
    expect(audit).toContain("SELECT COUNT(*) AS total");
    expect(audit).toContain("events: rows.map(scheduleAuditEventFromRow)");
    expect(audit).toContain("total,");
    expect(audit).toContain("limit,");
    expect(audit).toContain("offset,");
  });

  it("keeps organization authorization authoritative", () => {
    expect(routes).toContain("identity.role === ROLES.SYSTEM_ADMIN");
    expect(routes).toContain(
      "requestedOrganizationId !== identity.organizationId",
    );
    expect(routes).toContain('code: "AUDIT_ORGANIZATION_FORBIDDEN"');
    expect(routes).toContain("queryScheduleAuditEvents({");
  });

  it("dashboard consumes the paginated response shape", () => {
    expect(panel).toContain("type ScheduleAuditResponse");
    expect(panel).toContain("/games/schedule-audit/recent?");
    expect(panel).toContain("new URLSearchParams");
  });
});
