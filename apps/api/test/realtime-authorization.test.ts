import { describe, expect, it } from "vitest";
import { PERMISSIONS, ROLES, identityFromToken } from "../src/modules/auth/index.js";
import { authorizeRealtimeOrganization } from "../src/infrastructure/realtime.js";

describe("realtime protected subscription authorization", () => {
  const scorekeeper = identityFromToken({
    sub: "7",
    organizationId: 42,
    role: ROLES.SCOREKEEPER,
  });

  it("allows a permitted user to subscribe inside their organization", () => {
    expect(authorizeRealtimeOrganization(scorekeeper, 42, PERMISSIONS.GAME_READ)).toBe(true);

    expect(authorizeRealtimeOrganization(scorekeeper, 42, PERMISSIONS.SCOREBOARD_READ)).toBe(true);
  });

  it("denies a protected subscription for another organization", () => {
    expect(authorizeRealtimeOrganization(scorekeeper, 99, PERMISSIONS.GAME_READ)).toBe(false);
  });

  it("denies a protected subscription without an authenticated identity", () => {
    expect(authorizeRealtimeOrganization(null, 42, PERMISSIONS.GAME_READ)).toBe(false);
  });

  it("allows system administrators across organization boundaries", () => {
    const admin = identityFromToken({
      sub: "1",
      organizationId: 1,
      role: ROLES.SYSTEM_ADMIN,
    });

    expect(authorizeRealtimeOrganization(admin, 99, PERMISSIONS.GAME_READ)).toBe(true);
  });
});
