import { PERMISSIONS, roleHasPermission, type AuthenticatedIdentity } from "../auth/index.js";
import { canViewMedia, type MediaAccessDescriptor } from "../media-library/access-policy.js";

export interface RecordingAccessDescriptor {
  readonly organizationId: number;
  readonly ownerUserId: number | null;
  readonly media: MediaAccessDescriptor | null;
}

export function canViewRecording(
  identity: AuthenticatedIdentity,
  recording: RecordingAccessDescriptor,
): boolean {
  if (recording.ownerUserId === identity.userId) {
    return true;
  }

  if (recording.organizationId !== identity.organizationId) {
    return false;
  }

  if (recording.media) {
    return canViewMedia(identity, recording.media);
  }

  return roleHasPermission(identity.role, PERMISSIONS.STREAM_MANAGE);
}

export function canManageRecording(
  identity: AuthenticatedIdentity,
  recording: RecordingAccessDescriptor,
): boolean {
  if (recording.ownerUserId === identity.userId) {
    return true;
  }

  return (
    recording.organizationId === identity.organizationId &&
    roleHasPermission(identity.role, PERMISSIONS.STREAM_MANAGE)
  );
}
