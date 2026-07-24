import type { DomainEvent } from "./DomainEvent.js";

export interface EventPublisher {
  publish<TPayload>(event: DomainEvent<TPayload>): Promise<void>;

  publishMany<TPayload>(
    events: ReadonlyArray<DomainEvent<TPayload>>
  ): Promise<void>;
}