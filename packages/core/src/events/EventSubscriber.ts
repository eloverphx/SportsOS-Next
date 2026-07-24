import type { DomainEvent } from "./DomainEvent.js";

export interface EventSubscriber<TPayload = unknown> {
  readonly eventTypes: ReadonlyArray<string>;

  handle(event: DomainEvent<TPayload>): Promise<void>;
}