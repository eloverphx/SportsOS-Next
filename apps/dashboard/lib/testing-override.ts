export const SPORTSOS_TEST_OVERRIDE_STORAGE_KEY =
  "sportsos:tournament-game-operations:test-override";

export const SPORTSOS_TEST_OVERRIDE_EVENT =
  "sportsos:test-override-changed";

export function isLocalTestingHost(hostname: string): boolean {
  const host = hostname.trim().toLowerCase();

  if (
    host === "localhost" ||
    host === "127.0.0.1" ||
    host === "::1" ||
    host.endsWith(".local")
  ) {
    return true;
  }

  if (/^10\./.test(host) || /^192\.168\./.test(host)) {
    return true;
  }

  const match = host.match(/^172\.(\d{1,3})\./);
  if (match) {
    const secondOctet = Number(match[1]);
    return secondOctet >= 16 && secondOctet <= 31;
  }

  return false;
}

export function canUseTestingOverride(hostname: string): boolean {
  return (
    process.env.NEXT_PUBLIC_SPORTSOS_ENABLE_TEST_OVERRIDE === "true" ||
    isLocalTestingHost(hostname)
  );
}

export function readTestingOverride(
  storage: Pick<Storage, "getItem">,
): boolean {
  return storage.getItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY) === "enabled";
}

export function writeTestingOverride(
  storage: Pick<Storage, "setItem" | "removeItem">,
  enabled: boolean,
): void {
  if (enabled) storage.setItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY, "enabled");
  else storage.removeItem(SPORTSOS_TEST_OVERRIDE_STORAGE_KEY);
}

export function effectiveReadiness(
  actualReady: boolean,
  testingOverrideEnabled: boolean,
): boolean {
  return actualReady || testingOverrideEnabled;
}
