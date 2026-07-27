import { AppError } from "./AppError.js";

export class ConflictError extends AppError {
  constructor(message = "The requested operation conflicts with the current state.") {
    super(message, {
      statusCode: 409,
      code: "CONFLICT",
      expose: true,
    });
  }
}
