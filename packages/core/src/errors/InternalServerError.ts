import { AppError } from "./AppError.js";

export class InternalServerError extends AppError {
  constructor(message = "An unexpected internal error occurred.", cause?: unknown) {
    super(message, {
      statusCode: 500,
      code: "INTERNAL_SERVER_ERROR",
      cause,
      expose: false,
    });
  }
}
