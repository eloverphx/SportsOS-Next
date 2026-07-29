export class AuthorizationError extends Error {
  public readonly code = "AUTHORIZATION_DENIED";
  public readonly statusCode = 403;

  public constructor(message = "You do not have permission to perform this action") {
    super(message);
    this.name = "AuthorizationError";
  }
}
