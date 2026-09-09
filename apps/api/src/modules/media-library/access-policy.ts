import { PERMISSIONS, roleHasPermission, type AuthenticatedIdentity } from "../auth/index.js";

export type MediaVisibility = "PRIVATE" | "ORGANIZATION" | "PUBLIC";

export type MediaGrantPermission = "VIEW" | "EDIT" | "MANAGE";

export interface MediaAccessDescriptor {
  readonly organizationId: number | null;
  readonly ownerUserId: number | null;
  readonly visibility: MediaVisibility;
  readonly grantPermission: MediaGrantPermission | null;
}

function sameOrganization(identity: AuthenticatedIdentity, asset: MediaAccessDescriptor): boolean {
  return asset.organizationId !== null && identity.organizationId === asset.organizationId;
}

export function canViewMedia(
  identity: AuthenticatedIdentity | null,
  asset: MediaAccessDescriptor,
): boolean {
  if (asset.visibility === "PUBLIC") {
    return true;
  }

  if (!identity) {
    return false;
  }

  if (asset.ownerUserId === identity.userId) {
    return true;
  }

  if (!sameOrganization(identity, asset)) {
    return false;
  }

  if (asset.grantPermission !== null) {
    return true;
  }

  if (roleHasPermission(identity.role, PERMISSIONS.STREAM_MANAGE)) {
    return true;
  }

  return (
    asset.visibility === "ORGANIZATION" && roleHasPermission(identity.role, PERMISSIONS.STREAM_READ)
  );
}

export function canEditMedia(
  identity: AuthenticatedIdentity,
  asset: MediaAccessDescriptor,
): boolean {
  if (asset.ownerUserId === identity.userId) {
    return true;
  }

  if (!sameOrganization(identity, asset)) {
    return false;
  }

  if (asset.grantPermission === "EDIT" || asset.grantPermission === "MANAGE") {
    return true;
  }

  return roleHasPermission(identity.role, PERMISSIONS.STREAM_MANAGE);
}

export function canManageMedia(
  identity: AuthenticatedIdentity,
  asset: MediaAccessDescriptor,
): boolean {
  if (asset.ownerUserId === identity.userId) {
    return true;
  }

  if (!sameOrganization(identity, asset)) {
    return false;
  }

  if (asset.grantPermission === "MANAGE") {
    return true;
  }

  return roleHasPermission(identity.role, PERMISSIONS.STREAM_MANAGE);
}
