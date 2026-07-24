export interface RequestContext {
  requestId: string;
  timestamp: string;
  userId?: string;
  organizationId?: string;
  correlationId?: string;
}