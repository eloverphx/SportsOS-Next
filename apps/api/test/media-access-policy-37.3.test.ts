import { describe, expect, it } from "vitest";
import {
  permissionsForRole,
  ROLES,
  type AuthenticatedIdentity,
} from "../src/modules/auth/index.js";
import {
  canManageMedia,
  canViewMedia,
  type MediaAccessDescriptor,
} from "../src/modules/media-library/access-policy.js";

function identity(
  userId: number,
  organizationId: number,
  role: (typeof ROLES)[keyof typeof ROLES],
): AuthenticatedIdentity {
  return {
    sub: String(userId),
    userId,
    organizationId,
    role,
    permissions: permissionsForRole(role),
  };
}

function asset(overrides: Partial<MediaAccessDescriptor> = {}): MediaAccessDescriptor {
  return {
    organizationId: 10,
    ownerUserId: 20,
    visibility: "ORGANIZATION",
    grantPermission: null,
    ...overrides,
  };
}

describe("Milestone 37.3 media access policy", () => {
  it("allows anonymous access only to public media", () => {
    expect(canViewMedia(null, asset({ visibility: "PUBLIC" }))).toBe(true);

    expect(canViewMedia(null, asset({ visibility: "ORGANIZATION" }))).toBe(false);

    expect(canViewMedia(null, asset({ visibility: "PRIVATE" }))).toBe(false);
  });

  it("allows a same-organization viewer to read organization media", () => {
    expect(canViewMedia(identity(30, 10, ROLES.VIEWER), asset())).toBe(true);
  });

  it("does not expose private media to an ordinary same-organization viewer", () => {
    expect(canViewMedia(identity(30, 10, ROLES.VIEWER), asset({ visibility: "PRIVATE" }))).toBe(
      false,
    );
  });

  it("allows owners and explicit grantees to read private media", () => {
    expect(canViewMedia(identity(20, 10, ROLES.VIEWER), asset({ visibility: "PRIVATE" }))).toBe(
      true,
    );

    expect(
      canViewMedia(
        identity(30, 10, ROLES.VIEWER),
        asset({
          visibility: "PRIVATE",
          grantPermission: "VIEW",
        }),
      ),
    ).toBe(true);
  });

  it("allows same-organization stream managers to administer private media", () => {
    const admin = identity(30, 10, ROLES.ORGANIZATION_ADMIN);

    const privateAsset = asset({
      visibility: "PRIVATE",
    });

    expect(canViewMedia(admin, privateAsset)).toBe(true);

    expect(canManageMedia(admin, privateAsset)).toBe(true);
  });

  it("does not grant cross-organization access merely because a role can manage streams", () => {
    const otherOrganizationAdmin = identity(30, 99, ROLES.ORGANIZATION_ADMIN);

    const privateAsset = asset({
      visibility: "PRIVATE",
    });

    expect(canViewMedia(otherOrganizationAdmin, privateAsset)).toBe(false);

    expect(canManageMedia(otherOrganizationAdmin, privateAsset)).toBe(false);
  });
});
