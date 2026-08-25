export type SessionInvalidationCheck = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

export type SessionInvalidationReadinessResult = {
  ready: boolean;
  strategy: "jwt-secret-rotation";
  impact: {
    activeJwtTokensInvalidated: boolean;
    usersMustSignInAgain: boolean;
    serverSessionStoreRequired: boolean;
  };
  checks: SessionInvalidationCheck[];
};

export function evaluateSessionInvalidationReadiness(
  env: Record<string, string | undefined>,
): SessionInvalidationReadinessResult {
  const checks: SessionInvalidationCheck[] = [];

  const jwt =
    env.JWT_SECRET?.trim() ??
    "";

  checks.push({
    id:
      "jwt:configured",
    ok:
      jwt.length > 0,
    required:
      true,
    message:
      jwt
        ? "JWT secret is configured."
        : "JWT secret is missing.",
  });

  checks.push({
    id:
      "jwt:minimum-length",
    ok:
      jwt.length >=
      32,
    required:
      true,
    message:
      "JWT secret must be at least 32 characters before session invalidation by rotation is considered production-ready.",
  });

  checks.push({
    id:
      "runtime:production",
    ok:
      env.NODE_ENV ===
      "production",
    required:
      true,
    message:
      env.NODE_ENV === "production"
        ? "Runtime is production."
        : "Runtime must be production.",
  });

  return {
    ready:
      checks
        .filter(
          (check) =>
            check.required,
        )
        .every(
          (check) =>
            check.ok,
        ),
    strategy:
      "jwt-secret-rotation",
    impact: {
      activeJwtTokensInvalidated:
        true,
      usersMustSignInAgain:
        true,
      serverSessionStoreRequired:
        false,
    },
    checks,
  };
}
