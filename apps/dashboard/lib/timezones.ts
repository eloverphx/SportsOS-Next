const FALLBACK_AMERICAS_TIME_ZONES = [
  "America/Anchorage",
  "America/Argentina/Buenos_Aires",
  "America/Bogota",
  "America/Caracas",
  "America/Chicago",
  "America/Denver",
  "America/Detroit",
  "America/Edmonton",
  "America/Halifax",
  "America/Havana",
  "America/Indiana/Indianapolis",
  "America/Juneau",
  "America/La_Paz",
  "America/Lima",
  "America/Los_Angeles",
  "America/Manaus",
  "America/Mexico_City",
  "America/Monterrey",
  "America/Montevideo",
  "America/New_York",
  "America/Nome",
  "America/Panama",
  "America/Phoenix",
  "America/Puerto_Rico",
  "America/Regina",
  "America/Santiago",
  "America/Sao_Paulo",
  "America/St_Johns",
  "America/Tijuana",
  "America/Toronto",
  "America/Vancouver",
  "America/Winnipeg",
] as const;

function supportedAmericasTimeZones(): string[] {
  try {
    return Intl.supportedValuesOf("timeZone")
      .filter((timezone) => timezone.startsWith("America/"))
      .sort((left, right) => left.localeCompare(right));
  } catch {
    return [...FALLBACK_AMERICAS_TIME_ZONES];
  }
}

export const AMERICAS_TIME_ZONES = supportedAmericasTimeZones();
