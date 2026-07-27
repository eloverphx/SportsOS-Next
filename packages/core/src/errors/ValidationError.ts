import { AppError } from "./AppError.js";

export class ValidationError extends AppError {
  constructor(message = "The request data is invalid.", details?: unknown) {
    super(message, {
      statusCode: 400,
      code: "VALIDATION_ERROR",
      details,
      expose: true,
    });
  }
}
