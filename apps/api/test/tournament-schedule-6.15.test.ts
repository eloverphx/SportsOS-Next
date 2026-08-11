import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  SCHEDULE_AUDIT_ACTIONS,
} from "../src/modules/games/schedule-audit.js";

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

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

const page = readFileSync(
  new URL("../../dashboard/app/tournament-director/page.tsx", import.meta.url),
  "utf8",
);

describe("Tournament scheduling 6.15 audit visibility", () => {
  it("tracks blocked and overridden create/update schedule decisions", () => {
    expect(SCHEDULE_AUDIT_ACTIONS).toEqual([
      "game.schedule_create_conflict_blocked",
      "game.schedule_create_conflict_overridden",
      "game.schedule_conflict_blocked",
      "game.schedule_conflict_overridden",
    ]);
  });

  it("exposes a GAME_READ-protected schedule audit endpoint", () => {
    expect(routes).toContain('app.get("/games/schedule-audit/recent"');
    expect(routes).toContain("permission: PERMISSIONS.GAME_READ");
    expect(routes).toContain("queryScheduleAuditEvents(");
    expect(routes).toContain("identity.role === ROLES.SYSTEM_ADMIN");
    expect(routes).toContain(
      "requestedOrganizationId !== identity.organizationId",
    );
    expect(routes).toContain(
      ": identity.organizationId",
    );
  });

  it("joins actor identity and extracts schedule governance details", () => {
    expect(audit).toContain("LEFT JOIN users u ON u.id = a.user_id");
    expect(audit).toContain("actorName");
    expect(audit).toContain("actorRole");
    expect(audit).toContain("organizationId");
    expect(audit).toContain("reason");
    expect(audit).toContain("conflictCount");
  });

  it("renders a read-only decision history in Tournament Director", () => {
    expect(page).toContain("<TournamentScheduleAudit games={games} />");
    expect(panel).toContain('data-testid="director-audit"');
    expect(panel).toContain("Schedule decision history");
    expect(panel).toContain("Override reason");
    expect(panel).toContain("Actor:");
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });

  it("refreshes decision history without mutating schedule state", () => {
    expect(panel).toContain("/games/schedule-audit/recent?");
    expect(panel).toContain("window.setInterval");
    expect(panel).toContain("15_000");
  });
});
