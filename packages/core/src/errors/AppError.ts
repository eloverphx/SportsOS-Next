export interface AppErrorOptions {
  statusCode?: number;
  code?: string;
  details?: unknown;
  cause?: unknown;
  expose?: boolean;
}

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly code: string;
  public readonly details?: unknown;
  public readonly expose: boolean;

  constructor(message: string, options: AppErrorOptions = {}) {
    super(message, {
      cause: options.cause
    });

    this.name = new.target.name;
    this.statusCode = options.statusCode ?? 500;
    this.code = options.code ?? "INTERNAL_SERVER_ERROR";
    this.details = options.details;
    this.expose = options.expose ?? this.statusCode < 500;

    Object.setPrototypeOf(this, new.target.prototype);
  }
}