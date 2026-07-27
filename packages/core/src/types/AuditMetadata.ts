export interface AuditMetadata {
  requestId?: string;
  actorId?: string;
  organizationId?: string;
  source?: string;
  ipAddress?: string;
  userAgent?: string;
  occurredAt: string;
}
