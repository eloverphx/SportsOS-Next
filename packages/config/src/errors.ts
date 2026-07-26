import { ZodError } from 'zod';

export class ConfigurationError extends Error {
  public readonly issues: readonly string[];

  public constructor(issues: readonly string[]) {
    super(
      [
        'Invalid SportsOS configuration:',
        ...issues.map((issue) => `- ${issue}`)
      ].join('\n')
    );

    this.name = 'ConfigurationError';
    this.issues = issues;
  }
}

export function formatConfigurationError(error: ZodError): ConfigurationError {
  const issues = error.issues.map((issue) => {
    const field = issue.path.join('.') || 'environment';
    return `${field}: ${issue.message}`;
  });

  return new ConfigurationError(issues);
}
