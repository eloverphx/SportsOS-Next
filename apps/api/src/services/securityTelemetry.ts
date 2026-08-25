import {
  evaluateCredentialRotationReadiness,
} from "./credentialRotationReadiness.js";

import {
  validateSecretEnvironment,
} from "./secretEnvironmentValidation.js";

import {
  evaluateSecretSourceHardening,
} from "./secretSourceHardening.js";

import {
  evaluateSessionInvalidationReadiness,
} from "./sessionInvalidationReadiness.js";

export type SecurityTelemetryInput = {
  root: string;
  env: Record<string, string | undefined>;
  rollbackReady: boolean;
  dataMigrationReady: boolean;
};

export type SecurityTelemetryResult = {
  ready: boolean;
  sections: {
    credentialRotation: ReturnType<
      typeof evaluateCredentialRotationReadiness
    >;
    secretEnvironment: ReturnType<
      typeof validateSecretEnvironment
    >;
    secretSource: ReturnType<
      typeof evaluateSecretSourceHardening
    >;
    sessionInvalidation: ReturnType<
      typeof evaluateSessionInvalidationReadiness
    >;
  };
  blockers: string[];
};

export function evaluateSecurityTelemetry(
  input: SecurityTelemetryInput,
): SecurityTelemetryResult {
  const credentialRotation =
    evaluateCredentialRotationReadiness({
      env:
        input.env,
      rollbackReady:
        input.rollbackReady,
      dataMigrationReady:
        input.dataMigrationReady,
    });

  const secretEnvironment =
    validateSecretEnvironment(
      input.env,
    );

  const secretSource =
    evaluateSecretSourceHardening({
      root:
        input.root,
    });

  const sessionInvalidation =
    evaluateSessionInvalidationReadiness(
      input.env,
    );

  const sections = {
    credentialRotation,
    secretEnvironment,
    secretSource,
    sessionInvalidation,
  };

  const blockers =
    Object.entries(
      sections,
    ).flatMap(
      ([
        sectionName,
        section,
      ]) =>
        section.checks
          .filter(
            (check) =>
              check.required &&
              !check.ok,
          )
          .map(
            (check) =>
              `${sectionName}:${check.id}`,
          ),
    );

  return {
    ready:
      blockers.length ===
      0,
    sections,
    blockers,
  };
}
