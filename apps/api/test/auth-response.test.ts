import { describe, expect, it } from "vitest";
import { PERMISSIONS, ROLES, identityFromToken } from "../src/modules/auth/index.js";

describe("authenticated identity responses", () => {
  it("includes permissions derived from the authenticated role", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(identity).toMatchObject({
      userId: 12,
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(identity.permissions).toContain(PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE);

    expect(identity.permissions).toContain(PERMISSIONS.TEAM_CREATE);
  });

  it("does not expose management permissions to viewers", () => {
    const identity = identityFromToken({
      sub: "19",
      organizationId: 4,
      role: ROLES.VIEWER,
    });

    expect(identity.permissions).toContain(PERMISSIONS.ORGANIZATION_READ);

    expect(identity.permissions).not.toContain(PERMISSIONS.ORGANIZATION_UPDATE);

    expect(identity.permissions).not.toContain(PERMISSIONS.ORGANIZATION_MEMBERS_MANAGE);
  });
});
