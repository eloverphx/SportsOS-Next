import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  PERMISSIONS,
  ROLES,
  roleHasPermission,
} from "../src/modules/auth/index.js";

const routes = readFileSync(
  new URL("../src/modules/games/routes.ts", import.meta.url),
  "utf8",
);

const editor = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleEditor.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.13 override authorization", () => {
  it("defines schedule override as a distinct permission", () => {
    expect(PERMISSIONS.GAME_SCHEDULE_OVERRIDE).toBe(
      "game.schedule.override",
    );
    expect(PERMISSIONS.GAME_SCHEDULE_OVERRIDE).not.toBe(
      PERMISSIONS.GAME_MANAGE,
    );
  });

  it("grants override authority only to system admins and organization owners", () => {
    expect(
      roleHasPermission(ROLES.SYSTEM_ADMIN, PERMISSIONS.GAME_SCHEDULE_OVERRIDE),
    ).toBe(true);

    expect(
      roleHasPermission(
        ROLES.ORGANIZATION_OWNER,
        PERMISSIONS.GAME_SCHEDULE_OVERRIDE,
      ),
    ).toBe(true);

    expect(
      roleHasPermission(
        ROLES.ORGANIZATION_ADMIN,
        PERMISSIONS.GAME_SCHEDULE_OVERRIDE,
      ),
    ).toBe(false);

    expect(
      roleHasPermission(ROLES.TEAM_ADMIN, PERMISSIONS.GAME_SCHEDULE_OVERRIDE),
    ).toBe(false);

    expect(
      roleHasPermission(ROLES.SCOREKEEPER, PERMISSIONS.GAME_SCHEDULE_OVERRIDE),
    ).toBe(false);
  });

  it("requires elevated permission on both create and update override requests", () => {
    const postStart = routes.indexOf('app.post("/games"');
    const putStart = routes.indexOf('app.put("/games/:id"');
    const previewStart = routes.indexOf(
      'app.post("/games/:id/schedule-preview"',
      putStart,
    );

    const post = routes.slice(postStart, putStart);
    const put = routes.slice(putStart, previewStart);

    for (const route of [post, put]) {
      expect(route).toContain("if (scheduleOverride.override)");
      expect(route).toContain(
        "permission: PERMISSIONS.GAME_SCHEDULE_OVERRIDE",
      );
    }
  });

  it("checks override permission before entering the schedule transaction", () => {
    const postStart = routes.indexOf('app.post("/games"');
    const putStart = routes.indexOf('app.put("/games/:id"');
    const previewStart = routes.indexOf(
      'app.post("/games/:id/schedule-preview"',
      putStart,
    );

    const post = routes.slice(postStart, putStart);
    const put = routes.slice(putStart, previewStart);

    expect(post.indexOf("PERMISSIONS.GAME_SCHEDULE_OVERRIDE")).toBeLessThan(
      post.indexOf("createGameWithScheduleTransaction("),
    );

    expect(put.indexOf("PERMISSIONS.GAME_SCHEDULE_OVERRIDE")).toBeLessThan(
      put.indexOf("updateGameWithScheduleTransaction("),
    );
  });

  it("keeps normal scheduling separate from override authority in the UI", () => {
    expect(editor).toContain(
      "userHasPermission(user, PERMISSIONS.GAME_MANAGE)",
    );
    expect(editor).toContain("PERMISSIONS.GAME_SCHEDULE_OVERRIDE");
    expect(editor).toContain("canOverrideHardConflicts");
    expect(editor).toContain(
      "An organization owner or system administrator must approve",
    );
  });
});
