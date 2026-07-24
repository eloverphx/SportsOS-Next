import { AppError } from "./AppError.js";

export class NotFoundError extends AppError {
  constructor(resource = "Resource", identifier?: string) {
    const message = identifier
      ? `${resource} '${identifier}' was not found.`
      : `${resource} was not found.`;

    super(message, {
      statusCode: 404,
      code: "NOT_FOUND",
      expose: true
    });
  }
}