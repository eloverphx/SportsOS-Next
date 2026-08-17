export const SPORTSOS_TEAM_CHECKIN_STORAGE_PREFIX =
  "sportsos:tournament-game-operations:team-check-in";

export type TeamCheckInSide = "home" | "away";

export type TeamCheckInState = {
  home: boolean;
  away: boolean;
};

export const EMPTY_TEAM_CHECK_IN: TeamCheckInState = Object.freeze({
  home: false,
  away: false,
});

function storageKey(gameId: string): string {
  return `${SPORTSOS_TEAM_CHECKIN_STORAGE_PREFIX}:${gameId}`;
}

export function readTeamCheckIn(
  storage: Pick<Storage, "getItem">,
  gameId: string,
): TeamCheckInState {
  const raw = storage.getItem(storageKey(gameId));

  if (!raw) {
    return { ...EMPTY_TEAM_CHECK_IN };
  }

  try {
    const parsed = JSON.parse(raw) as Partial<TeamCheckInState>;
    return {
      home: parsed.home === true,
      away: parsed.away === true,
    };
  } catch {
    return { ...EMPTY_TEAM_CHECK_IN };
  }
}

export function writeTeamCheckIn(
  storage: Pick<Storage, "setItem">,
  gameId: string,
  state: TeamCheckInState,
): void {
  storage.setItem(storageKey(gameId), JSON.stringify(state));
}

export function setTeamCheckedIn(
  state: TeamCheckInState,
  side: TeamCheckInSide,
  checkedIn: boolean,
): TeamCheckInState {
  return {
    ...state,
    [side]: checkedIn,
  };
}

export function areBothTeamsCheckedIn(state: TeamCheckInState): boolean {
  return state.home && state.away;
}
