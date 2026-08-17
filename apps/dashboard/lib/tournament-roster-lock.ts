export const SPORTSOS_ROSTER_LOCK_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:roster-lock";

export type RosterLockSide = "home" | "away";

export type RosterLockState = {
  home: boolean;
  away: boolean;
};

export const EMPTY_ROSTER_LOCK_STATE: RosterLockState = Object.freeze({
  home: false,
  away: false,
});

function storageKey(gameId: string): string {
  return `${SPORTSOS_ROSTER_LOCK_STORAGE_PREFIX}:${gameId}`;
}

export function readRosterLockState(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): RosterLockState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return { ...EMPTY_ROSTER_LOCK_STATE };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<RosterLockState>;

    return {
      home: parsed.home === true,
      away: parsed.away === true,
    };
  } catch {
    return { ...EMPTY_ROSTER_LOCK_STATE };
  }
}

export function writeRosterLockState(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: RosterLockState,
): void {
  storage.setItem(storageKey(gameId), JSON.stringify(state));
}

export function setRosterLocked(
  state: RosterLockState,
  side: RosterLockSide,
  locked: boolean,
): RosterLockState {
  return {
    ...state,
    [side]: locked,
  };
}

export function areBothRostersLocked(state: RosterLockState): boolean {
  return state.home && state.away;
}

export function canLockRoster(
  checkedIn: boolean,
  testingOverrideEnabled: boolean,
): boolean {
  return checkedIn || testingOverrideEnabled;
}
