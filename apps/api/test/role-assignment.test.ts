import { describe, expect, it } from "vitest";
import {
  AuthorizationError,
  ROLES,
  assertRoleAssignmentAllowed,
  identityFromToken,
} from "../src/modules/auth/index.js";

describe("organization role assignment", () => {
  it("allows an organization administrator to assign team roles", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(() => assertRoleAssignmentAllowed(identity, ROLES.COACH)).not.toThrow();
  });

  it("prevents an organization administrator from assigning system admin", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(() => assertRoleAssignmentAllowed(identity, ROLES.SYSTEM_ADMIN)).toThrow(
      AuthorizationError,
    );
  });

  it("prevents an organization administrator from assigning owner", () => {
    const identity = identityFromToken({
      sub: "12",
      organizationId: 4,
      role: ROLES.ORGANIZATION_ADMIN,
    });

    expect(() => assertRoleAssignmentAllowed(identity, ROLES.ORGANIZATION_OWNER)).toThrow(
      "Only a system administrator can assign the organization owner role",
    );
  });

  it("allows a system administrator to assign owner", () => {
    const identity = identityFromToken({
      sub: "1",
      organizationId: 1,
      role: ROLES.SYSTEM_ADMIN,
    });

    expect(() => assertRoleAssignmentAllowed(identity, ROLES.ORGANIZATION_OWNER)).not.toThrow();
  });
});
