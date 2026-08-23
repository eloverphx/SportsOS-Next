export function resolveStreamCredential(
  credentialRef: string | null,
): string {
  const normalized =
    credentialRef?.trim() ??
    "";

  if (!normalized) {
    throw new Error(
      "Stream credential reference is required.",
    );
  }

  if (
    !normalized.startsWith(
      "env://",
    )
  ) {
    throw new Error(
      "Unsupported credential reference. Milestone 20.5 supports env://NAME only.",
    );
  }

  const variableName =
    normalized.slice(
      "env://".length,
    );

  if (
    !/^[A-Z_][A-Z0-9_]*$/.test(
      variableName,
    )
  ) {
    throw new Error(
      "Invalid environment credential reference.",
    );
  }

  const secret =
    process.env[
      variableName
    ]?.trim();

  if (!secret) {
    throw new Error(
      `Credential environment variable ${variableName} is not configured.`,
    );
  }

  return secret;
}
