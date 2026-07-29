import { describe, expect, it } from "vitest";
import {
  AuthorizationError,
  PERMISSIONS,
  ROLES,
  assertPermission,
  identityFromToken,
} from "../src/modules/auth/index.js";

describe("authorization enforcement", () => {
  it("allows an organization administrator to create a team", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.TEAM_CREATE,
        organizationId: 4,
      }),
    ).not.toThrow();
  });

  it("rejects a viewer attempting to create a team", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.VIEWER,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.TEAM_CREATE,
        organizationId: 4,
      }),
    ).toThrow(AuthorizationError);
  });

  it("rejects access to a different organization", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.TEAM_UPDATE,
        organizationId: 9,
      }),
    ).toThrow("You do not have access to this organization");
  });

  it("allows a system administrator across organizations", () => {
    const identity = identityFromToken({
      sub: "1",
      organizationId: 1,
      role: ROLES.SYSTEM_ADMIN,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.ORGANIZATION_UPDATE,
        organizationId: 99,
      }),
    ).not.toThrow();
  });

  it("allows scorekeepers to score games", () => {
    const identity = identityFromToken({
      sub: "18",
      organizationId: 4,
      role: ROLES.SCOREKEEPER,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.GAME_SCORE,
        organizationId: 4,
      }),
    ).not.toThrow();
  });

  it("does not allow scorekeepers to delete teams", () => {
    const identity = identityFromToken({
      sub: "18",
      organizationId: 4,
      role: ROLES.SCOREKEEPER,
    });

    expect(() =>
      assertPermission(identity, {
        permission: PERMISSIONS.TEAM_DELETE,
        organizationId: 4,
      }),
    ).toThrow(AuthorizationError);
  });
});
