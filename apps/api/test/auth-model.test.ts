import { describe, expect, it } from "vitest";
import {
  PERMISSIONS,
  ROLES,
  identityFromToken,
  normalizeRole,
  roleHasPermission,
} from "../src/modules/auth/index.js";

describe("authentication model", () => {
  it("maps the legacy admin role to organization admin", () => {
    expect(normalizeRole("admin")).toBe(
      ROLES.ORGANIZATION_ADMIN,
    );
  });

  it("normalizes canonical roles", () => {
    expect(normalizeRole("SCOREKEEPER")).toBe(
      ROLES.SCOREKEEPER,
    );
  });

  it("falls back to viewer for unknown roles", () => {
    expect(normalizeRole("unknown-role")).toBe(ROLES.VIEWER);
  });

  it("builds an authenticated identity from a JWT payload", () => {
    const identity = identityFromToken({
      sub: "42",
      organizationId: 7,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(identity).toMatchObject({
      sub: "42",
      userId: 42,
      organizationId: 7,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(identity.permissions).toContain(
      PERMISSIONS.TEAM_CREATE,
    );
  });

  it("allows scorekeepers to score games", () => {
    expect(
      roleHasPermission(
        ROLES.SCOREKEEPER,
        PERMISSIONS.GAME_SCORE,
      ),
    ).toBe(true);
  });

  it("does not allow viewers to manage games", () => {
    expect(
      roleHasPermission(
        ROLES.VIEWER,
        PERMISSIONS.GAME_MANAGE,
      ),
    ).toBe(false);
  });

  it("rejects an invalid JWT subject", () => {
    expect(() =>
      identityFromToken({
        sub: "not-a-number",
        organizationId: 7,
        role: ROLES.VIEWER,
      }),
    ).toThrow("Authenticated user identifier is invalid");
  });
});