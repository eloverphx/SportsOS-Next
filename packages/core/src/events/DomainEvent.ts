export interface DomainEventMetadata {
  requestId?: string;
  correlationId?: string;
  causationId?: string;
  actorId?: string;
  organizationId?: string;
  source?: string;
}

export interface DomainEvent<TPayload = unknown> {
  id: string;
  type: string;
  version: number;
  aggregateId: string;
  aggregateType: string;
  occurredAt: string;
  payload: TPayload;
  metadata?: DomainEventMetadata;
}