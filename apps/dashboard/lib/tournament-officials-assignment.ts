export const SPORTSOS_OFFICIALS_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:officials";

export type OfficialsAssignmentState = {
  referee1: string;
  referee2: string;
  linesman1: string;
  linesman2: string;
};

export const EMPTY_OFFICIALS_ASSIGNMENT: OfficialsAssignmentState =
  Object.freeze({
    referee1: "",
    referee2: "",
    linesman1: "",
    linesman2: "",
  });

function storageKey(gameId: string): string {
  return `${SPORTSOS_OFFICIALS_STORAGE_PREFIX}:${gameId}`;
}

export function normalizeOfficialName(value: string): string {
  return value.trim().replace(/\s+/g, " ");
}

export function readOfficialsAssignment(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): OfficialsAssignmentState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return { ...EMPTY_OFFICIALS_ASSIGNMENT };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<OfficialsAssignmentState>;

    return {
      referee1: normalizeOfficialName(parsed.referee1 ?? ""),
      referee2: normalizeOfficialName(parsed.referee2 ?? ""),
      linesman1: normalizeOfficialName(parsed.linesman1 ?? ""),
      linesman2: normalizeOfficialName(parsed.linesman2 ?? ""),
    };
  } catch {
    return { ...EMPTY_OFFICIALS_ASSIGNMENT };
  }
}

export function writeOfficialsAssignment(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: OfficialsAssignmentState,
): void {
  storage.setItem(
    storageKey(gameId),
    JSON.stringify({
      referee1: normalizeOfficialName(state.referee1),
      referee2: normalizeOfficialName(state.referee2),
      linesman1: normalizeOfficialName(state.linesman1),
      linesman2: normalizeOfficialName(state.linesman2),
    }),
  );
}

export function hasRequiredOfficials(
  state: OfficialsAssignmentState,
): boolean {
  return (
    normalizeOfficialName(state.referee1).length > 0 &&
    normalizeOfficialName(state.referee2).length > 0
  );
}

export function hasCompleteOfficialsCrew(
  state: OfficialsAssignmentState,
): boolean {
  return (
    hasRequiredOfficials(state) &&
    normalizeOfficialName(state.linesman1).length > 0 &&
    normalizeOfficialName(state.linesman2).length > 0
  );
}
