import { AppError } from "./AppError.js";

export class ForbiddenError extends AppError {
  constructor(message = "You do not have permission to perform this action.") {
    super(message, {
      statusCode: 403,
      code: "FORBIDDEN",
      expose: true,
    });
  }
}
