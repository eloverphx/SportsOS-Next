import type { Logger } from "./Logger.js";
import type { LogMetadata } from "./LogMetadata.js";

export class ConsoleLogger implements Logger {
  debug(message: string, metadata?: LogMetadata): void {
    console.debug(message, metadata ?? {});
  }

  info(message: string, metadata?: LogMetadata): void {
    console.info(message, metadata ?? {});
  }

  warn(message: string, metadata?: LogMetadata): void {
    console.warn(message, metadata ?? {});
  }

  error(message: string, metadata?: LogMetadata): void {
    console.error(message, metadata ?? {});
  }

  child(metadata: LogMetadata): Logger {
    return new ChildLogger(this, metadata);
  }
}

class ChildLogger implements Logger {
  constructor(
    private readonly parent: Logger,
    private readonly defaults: LogMetadata
  ) {}

  debug(message: string, metadata?: LogMetadata): void {
    this.parent.debug(message, {
      ...this.defaults,
      ...metadata
    });
  }

  info(message: string, metadata?: LogMetadata): void {
    this.parent.info(message, {
      ...this.defaults,
      ...metadata
    });
  }

  warn(message: string, metadata?: LogMetadata): void {
    this.parent.warn(message, {
      ...this.defaults,
      ...metadata
    });
  }

  error(message: string, metadata?: LogMetadata): void {
    this.parent.error(message, {
      ...this.defaults,
      ...metadata
    });
  }

  child(metadata: LogMetadata): Logger {
    return new ChildLogger(this.parent, {
      ...this.defaults,
      ...metadata
    });
  }
}