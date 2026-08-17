"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  extractTournamentGame,
  extractTournamentGameList,
  readinessCount,
  type TournamentGameOperationsGame,
} from "../../lib/tournament-game-operations";
import {
  SPORTSOS_TEST_OVERRIDE_EVENT,
  canUseTestingOverride,
  effectiveReadiness,
  readTestingOverride,
  writeTestingOverride,
} from "../../lib/testing-override";
import {
  buildPregameReadinessSummary,
  type PregameReadinessCheck,
} from "../../lib/tournament-pregame-readiness";
import {
  areBothTeamsCheckedIn,
  readTeamCheckIn,
  setTeamCheckedIn,
  writeTeamCheckIn,
  type TeamCheckInSide,
  type TeamCheckInState,
} from "../../lib/tournament-team-check-in";
import {
  areBothRostersLocked,
  canLockRoster,
  readRosterLockState,
  setRosterLocked,
  writeRosterLockState,
  type RosterLockSide,
  type RosterLockState,
} from "../../lib/tournament-roster-lock";
import {
  hasCompleteOfficialsCrew,
  hasRequiredOfficials,
  readOfficialsAssignment,
  writeOfficialsAssignment,
  type OfficialsAssignmentState,
} from "../../lib/tournament-officials-assignment";
import {
  canAuthorizeGameStart,
  clearGameStartAuthorization,
  createGameStartAuthorization,
  readGameStartAuthorization,
  writeGameStartAuthorization,
  type GameStartAuthorizationRecord,
} from "../../lib/tournament-game-start-authorization";
import { GameLiveTransitionControl } from "./GameLiveTransitionControl";
import { GameResultFinalizationControl } from "./GameResultFinalizationControl";
import {
  buildTournamentOperationsSummary,
} from "../../lib/tournament-operations-dashboard";

type LoadState = "idle" | "loading" | "ready" | "error";

function formatStart(value: string | null): string {
  if (!value) return "Not scheduled";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

function StatusBadge({ value }: { value: string }) {
  return (
    <span className="rounded-full border border-slate-700 bg-slate-900 px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-slate-200">
      {value}
    </span>
  );
}

function ReadinessStateBadge({
  state,
}: {
  state: PregameReadinessCheck["state"];
}) {
  const label =
    state === "PASS"
      ? "Ready"
      : state === "BLOCKED"
        ? "Blocked"
        : state === "WARNING"
          ? "Warning"
          : "Unknown";

  const className =
    state === "PASS"
      ? "text-emerald-400"
      : state === "BLOCKED"
        ? "text-red-400"
        : state === "WARNING"
          ? "text-amber-400"
          : "text-slate-400";

  return <span className={`text-sm font-semibold ${className}`}>{label}</span>;
}

function PregameReadinessRow({
  check,
}: {
  check: PregameReadinessCheck;
}) {
  return (
    <div className="rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-semibold text-slate-200">
              {check.label}
            </span>
            <span className="rounded-full border border-slate-800 px-2 py-0.5 text-[10px] uppercase tracking-wide text-slate-500">
              {check.severity}
            </span>
          </div>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            {check.detail}
          </p>
        </div>
        <ReadinessStateBadge state={check.state} />
      </div>
    </div>
  );
}

function ReadinessRow({
  label,
  ready,
}: {
  label: string;
  ready: boolean;
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border border-slate-800 bg-slate-950/60 px-3 py-2">
      <span className="text-sm text-slate-300">{label}</span>
      <span
        className={
          ready
            ? "text-sm font-semibold text-emerald-400"
            : "text-sm font-semibold text-amber-400"
        }
      >
        {ready ? "Ready" : "Needs attention"}
      </span>
    </div>
  );
}

function FutureAction({
  title,
  milestone,
  description,
}: {
  title: string;
  milestone: string;
  description: string;
}) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="font-semibold text-slate-100">{title}</h3>
          <p className="mt-1 text-sm text-slate-400">{description}</p>
        </div>
        <span className="whitespace-nowrap rounded-full border border-slate-700 px-2 py-1 text-xs text-slate-400">
          {milestone}
        </span>
      </div>
      <button
        type="button"
        disabled
        className="mt-4 w-full cursor-not-allowed rounded-lg border border-slate-800 bg-slate-900 px-3 py-2 text-sm font-semibold text-slate-500"
      >
        Not enabled in 7.1
      </button>
    </div>
  );
}

export function TournamentGameOperationsWorkspace() {
  const [gameStartAuthorization, setGameStartAuthorization] =
    useState<GameStartAuthorizationRecord | null>(null);
  const [authorizationOperator, setAuthorizationOperator] = useState("");
  const [authorizationOverrideReason, setAuthorizationOverrideReason] =
    useState("");

  const [teamCheckInState, setTeamCheckInState] =
    useState<TeamCheckInState>({
      home: false,
      away: false,
    });
  const [rosterLockState, setRosterLockState] =
    useState<RosterLockState>({
      home: false,
      away: false,
    });
  const [officialsAssignment, setOfficialsAssignment] =
    useState<OfficialsAssignmentState>({
      referee1: "",
      referee2: "",
      linesman1: "",
      linesman2: "",
    });

  const [games, setGames] = useState<TournamentGameOperationsGame[]>([]);
  const [selectedGame, setSelectedGame] =
    useState<TournamentGameOperationsGame | null>(null);
  const [gameId, setGameId] = useState("");
  const [listState, setListState] = useState<LoadState>("idle");
  const [gameState, setGameState] = useState<LoadState>("idle");
  const [message, setMessage] = useState<string | null>(null);
  const [testingOverrideAvailable, setTestingOverrideAvailable] =
    useState(false);
  const [testingOverrideEnabled, setTestingOverrideEnabled] =
    useState(false);

  const loadGame = useCallback(async (requestedGameId: string) => {
    const normalized = requestedGameId.trim();
    if (!normalized) return;

    setGameState("loading");
    setMessage(null);

    try {
      const response = await fetch(
        `/api/tournament/game-operations/${encodeURIComponent(normalized)}`,
        { cache: "no-store" },
      );

      if (!response.ok) {
        throw new Error(`Game request failed with status ${response.status}.`);
      }

      const payload: unknown = await response.json();
      const game = extractTournamentGame(payload);

      if (!game) {
        throw new Error("The API response did not contain a recognizable game.");
      }

      setSelectedGame(game);
      setGameId(game.id);
      setGameState("ready");

      const url = new URL(window.location.href);
      url.searchParams.set("gameId", game.id);
      window.history.replaceState({}, "", url);
    } catch (error) {
      setSelectedGame(null);
      setGameState("error");
      setMessage(
        error instanceof Error ? error.message : "Unable to load the game.",
      );
    }
  }, []);

  useEffect(() => {
    const available = canUseTestingOverride(window.location.hostname);
    setTestingOverrideAvailable(available);
    setTestingOverrideEnabled(
      available ? readTestingOverride(window.localStorage) : false,
    );

    const handleOverrideChange = () => {
      setTestingOverrideEnabled(
        available ? readTestingOverride(window.localStorage) : false,
      );
    };

    window.addEventListener(
      SPORTSOS_TEST_OVERRIDE_EVENT,
      handleOverrideChange,
    );

    return () => {
      window.removeEventListener(
        SPORTSOS_TEST_OVERRIDE_EVENT,
        handleOverrideChange,
      );
    };
  }, []);

  useEffect(() => {
    let active = true;

    async function loadGames() {
      setListState("loading");

      try {
        const response = await fetch("/api/tournament/game-operations", {
          cache: "no-store",
        });

        if (!response.ok) {
          throw new Error(
            `Scheduled game request failed with status ${response.status}.`,
          );
        }

        const payload: unknown = await response.json();
        const normalizedGames = extractTournamentGameList(payload);

        if (!active) return;

        setGames(normalizedGames);
        setListState("ready");

        const initialGameId = new URL(window.location.href).searchParams.get(
          "gameId",
        );

        if (initialGameId) {
          setGameId(initialGameId);
          void loadGame(initialGameId);
        }
      } catch (error) {
        if (!active) return;
        setListState("error");
        setMessage(
          error instanceof Error
            ? error.message
            : "Unable to load scheduled games.",
        );
      }
    }

    void loadGames();

    return () => {
      active = false;
    };
  }, [loadGame]);

  const selectedReadiness = useMemo(
    () => (selectedGame ? readinessCount(selectedGame) : null),
    [selectedGame],
  );

  const effectiveReadinessCount = useMemo(() => {
    if (!selectedGame || !selectedReadiness) return null;

    if (testingOverrideEnabled) {
      return {
        passed: selectedReadiness.total,
        total: selectedReadiness.total,
      };
    }

    return selectedReadiness;
  }, [selectedGame, selectedReadiness, testingOverrideEnabled]);

    useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setTeamCheckInState({
        home: false,
        away: false,
      });
      return;
    }

    setTeamCheckInState(
      readTeamCheckIn(window.localStorage, selectedGame.id),
    );
  }, [selectedGame]);

  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setRosterLockState({
        home: false,
        away: false,
      });
      return;
    }

    setRosterLockState(
      readRosterLockState(window.localStorage, selectedGame.id),
    );
  }, [selectedGame]);

  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setOfficialsAssignment({
        referee1: "",
        referee2: "",
        linesman1: "",
        linesman2: "",
      });
      return;
    }

    setOfficialsAssignment(
      readOfficialsAssignment(
        window.localStorage,
        selectedGame.id,
      ),
    );
  }, [selectedGame]);

  useEffect(() => {
    if (!selectedGame || typeof window === "undefined") {
      setGameStartAuthorization(null);
      setAuthorizationOperator("");
      setAuthorizationOverrideReason("");
      return;
    }

    const existing = readGameStartAuthorization(
      window.localStorage,
      selectedGame.id,
    );

    setGameStartAuthorization(existing);
    setAuthorizationOperator(existing?.authorizedBy ?? "");
    setAuthorizationOverrideReason(
      existing?.overrideReason ?? "",
    );
  }, [selectedGame]);

const pregameReadinessSummary = useMemo(
    () =>
      selectedGame
        ? buildPregameReadinessSummary(
            selectedGame,
            testingOverrideEnabled,
            {
              teamCheckInReady:
                areBothTeamsCheckedIn(teamCheckInState),
              rosterLockReady:
                areBothRostersLocked(rosterLockState),
              officialsReady:
                hasRequiredOfficials(officialsAssignment),
            },
          )
        : null,
    [officialsAssignment, selectedGame, rosterLockState, teamCheckInState, testingOverrideEnabled],
  );

      const tournamentOperationsSummary = useMemo(() => {
    if (!pregameReadinessSummary) {
      return null;
    }

    return buildTournamentOperationsSummary({
      actualReady: pregameReadinessSummary.actualReady,
      effectiveReady: pregameReadinessSummary.effectiveReady,
      homeCheckedIn: teamCheckInState.home,
      awayCheckedIn: teamCheckInState.away,
      homeRosterLocked: rosterLockState.home,
      awayRosterLocked: rosterLockState.away,
      officialsReady: hasRequiredOfficials(officialsAssignment),
      startAuthorized: Boolean(gameStartAuthorization),
      liveStarted: false,
      finalized: false,
    });
  }, [
    gameStartAuthorization,
    officialsAssignment,
    pregameReadinessSummary,
    rosterLockState,
    teamCheckInState,
  ]);

const updateTeamCheckIn = (
    side: TeamCheckInSide,
    checkedIn: boolean,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const nextState = setTeamCheckedIn(
      teamCheckInState,
      side,
      checkedIn,
    );

    setTeamCheckInState(nextState);
    writeTeamCheckIn(
      window.localStorage,
      selectedGame.id,
      nextState,
    );
  };

  const updateRosterLock = (
    side: RosterLockSide,
    locked: boolean,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const checkedIn = teamCheckInState[side];

    if (
      locked &&
      !canLockRoster(
        checkedIn,
        testingOverrideEnabled,
      )
    ) {
      return;
    }

    const nextState = setRosterLocked(
      rosterLockState,
      side,
      locked,
    );

    setRosterLockState(nextState);
    writeRosterLockState(
      window.localStorage,
      selectedGame.id,
      nextState,
    );
  };

  const updateOfficialAssignment = (
    field: keyof OfficialsAssignmentState,
    value: string,
  ) => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    const nextState = {
      ...officialsAssignment,
      [field]: value,
    };

    setOfficialsAssignment(nextState);
    writeOfficialsAssignment(
      window.localStorage,
      selectedGame.id,
      nextState,
    );
  };

  const authorizeGameStart = () => {
    if (
      !selectedGame ||
      !pregameReadinessSummary ||
      typeof window === "undefined"
    ) {
      return;
    }

    const record = createGameStartAuthorization({
      gameId: selectedGame.id,
      authorizedBy: authorizationOperator,
      actualReady: pregameReadinessSummary.actualReady,
      effectiveReady: pregameReadinessSummary.effectiveReady,
      testingOverrideEnabled,
      overrideReason: authorizationOverrideReason,
    });

    writeGameStartAuthorization(
      window.localStorage,
      record,
    );

    setGameStartAuthorization(record);
  };

  const revokeGameStartAuthorization = () => {
    if (!selectedGame || typeof window === "undefined") {
      return;
    }

    clearGameStartAuthorization(
      window.localStorage,
      selectedGame.id,
    );

    setGameStartAuthorization(null);
  };

const toggleTestingOverride = () => {
    if (!testingOverrideAvailable) return;

    const next = !testingOverrideEnabled;
    writeTestingOverride(window.localStorage, next);
    setTestingOverrideEnabled(next);
    window.dispatchEvent(new Event(SPORTSOS_TEST_OVERRIDE_EVENT));
  };

  return (
    <section className="space-y-6" data-testid="game-operations-workspace">
      <header className="space-y-2">
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="text-3xl font-bold tracking-tight text-slate-100">
            Tournament Game Operations
          </h1>
          <StatusBadge value="Milestone 7.1" />
        </div>
        <p className="max-w-3xl text-sm text-slate-400">
          Select a tournament game and review the operational context that will
          drive pregame readiness, game start authorization, live scoring, and
          finalization in the remaining Milestone 7 work.
        </p>
      </header>

      {testingOverrideAvailable ? (
        <div
          data-testid="testing-override-panel"
          className={
            testingOverrideEnabled
              ? "rounded-xl border border-amber-500/70 bg-amber-950/30 p-4"
              : "rounded-xl border border-slate-800 bg-slate-950/40 p-4"
          }
        >
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <h2 className="font-semibold text-slate-100">
                  Testing override
                </h2>
                <span
                  data-testid="testing-override-status"
                  className={
                    testingOverrideEnabled
                      ? "rounded-full border border-amber-500/60 px-2 py-0.5 text-xs font-bold uppercase tracking-wide text-amber-300"
                      : "rounded-full border border-slate-700 px-2 py-0.5 text-xs font-semibold uppercase tracking-wide text-slate-400"
                  }
                >
                  {testingOverrideEnabled ? "ENABLED" : "OFF"}
                </span>
              </div>
              <p className="mt-1 max-w-3xl text-sm text-slate-400">
                Local-development helper. When enabled, readiness gates added
                during Milestone 7 may treat missing setup information as
                satisfied so game workflows can be exercised before every
                dependency is configured. Actual readiness remains visible.
              </p>
            </div>

            <button
              type="button"
              data-testid="testing-override-toggle"
              onClick={toggleTestingOverride}
              className={
                testingOverrideEnabled
                  ? "rounded-lg border border-amber-500/60 bg-amber-500/10 px-4 py-2 text-sm font-semibold text-amber-300"
                  : "rounded-lg border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-slate-200"
              }
            >
              {testingOverrideEnabled
                ? "Disable testing override"
                : "Enable testing override"}
            </button>
          </div>

          {testingOverrideEnabled ? (
            <p className="mt-3 text-xs font-semibold text-amber-300">
              TESTING OVERRIDE ACTIVE — missing readiness data may be bypassed.
              This does not change the stored game data.
            </p>
          ) : null}
        </div>
      ) : null}

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
        <label
          htmlFor="game-operations-select"
          className="text-sm font-semibold text-slate-200"
        >
          Scheduled game
        </label>

        <div className="mt-2 flex flex-col gap-2 lg:flex-row">
          <select
            id="game-operations-select"
            data-testid="game-operations-select"
            value={gameId}
            onChange={(event) => {
              const value = event.target.value;
              setGameId(value);
              if (value) void loadGame(value);
            }}
            className="min-h-10 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 text-sm text-slate-100"
          >
            <option value="">
              {listState === "loading"
                ? "Loading scheduled games..."
                : "Select a game"}
            </option>
            {games.map((game) => (
              <option key={game.id} value={game.id}>
                {game.homeTeamName} vs {game.awayTeamName} —{" "}
                {formatStart(game.scheduledStart)}
              </option>
            ))}
          </select>

          <div className="flex min-w-0 flex-1 gap-2">
            <input
              aria-label="Game ID"
              data-testid="game-operations-game-id"
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="Or enter game ID"
              className="min-h-10 min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 text-sm text-slate-100"
            />
            <button
              type="button"
              data-testid="game-operations-load"
              disabled={!gameId.trim() || gameState === "loading"}
              onClick={() => void loadGame(gameId)}
              className="rounded-lg bg-slate-100 px-4 py-2 text-sm font-semibold text-slate-950 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {gameState === "loading" ? "Loading..." : "Load"}
            </button>
          </div>
        </div>

        {message ? (
          <p
            role="alert"
            className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-sm text-amber-300"
          >
            {message}
          </p>
        ) : null}
      </div>

      {!selectedGame ? (
        <div className="rounded-xl border border-dashed border-slate-700 p-8 text-center text-slate-400">
          Select a scheduled game to open its operations workspace.
        </div>
      ) : (
        <>
          <div className="grid gap-4 xl:grid-cols-3">
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5 xl:col-span-2">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Selected game
                  </p>
                  <h2
                    data-testid="game-operations-matchup"
                    className="mt-1 text-2xl font-bold text-slate-100"
                  >
                    {selectedGame.homeTeamName} vs{" "}
                    {selectedGame.awayTeamName}
                  </h2>
                </div>
                <StatusBadge value={selectedGame.status} />
              </div>

              <dl className="mt-5 grid gap-4 sm:grid-cols-2">
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Game ID
                  </dt>
                  <dd className="mt-1 break-all text-sm text-slate-200">
                    {selectedGame.id}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Scheduled start
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {formatStart(selectedGame.scheduledStart)}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Venue
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.venueName ?? "Not assigned"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Rink
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.rinkName ?? "Not assigned"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs uppercase tracking-wide text-slate-500">
                    Scoring status
                  </dt>
                  <dd className="mt-1 text-sm text-slate-200">
                    {selectedGame.scoringStatus}
                  </dd>
                </div>
              </dl>
            </div>

                                    {tournamentOperationsSummary ? (
              <section
                data-testid="tournament-operations-overview"
                className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
              >
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Tournament operations
                    </div>
                    <h2 className="mt-1 text-xl font-bold text-slate-100">
                      {tournamentOperationsSummary.stage}
                    </h2>
                  </div>

                  <div className="text-right">
                    <div className="text-2xl font-bold text-slate-100">
                      {tournamentOperationsSummary.completionPercent}%
                    </div>
                    <div className="text-xs text-slate-500">
                      {tournamentOperationsSummary.completedSteps} /{" "}
                      {tournamentOperationsSummary.totalSteps} operational steps
                    </div>
                  </div>
                </div>

                <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
                  <div
                    className="h-full bg-slate-400 transition-all"
                    style={{
                      width: `${tournamentOperationsSummary.completionPercent}%`,
                    }}
                  />
                </div>

                {tournamentOperationsSummary.blockers.length > 0 ? (
                  <div className="mt-4">
                    <div className="text-xs font-semibold uppercase tracking-wide text-amber-400">
                      Current blockers
                    </div>
                    <div className="mt-2 grid gap-2 md:grid-cols-2">
                      {tournamentOperationsSummary.blockers.map(
                        (blocker) => (
                          <div
                            key={blocker}
                            className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                          >
                            {blocker}
                          </div>
                        ),
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="mt-4 rounded-lg border border-emerald-900/50 bg-emerald-950/20 px-3 py-2 text-xs text-emerald-300">
                    No current operational blockers.
                  </div>
                )}
              </section>
            ) : null}

<section
              data-testid="team-check-in-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Team check-in
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Confirm each team has arrived and reported for this game.
                  </p>
                </div>

                <span
                  className={
                    areBothTeamsCheckedIn(teamCheckInState)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {areBothTeamsCheckedIn(teamCheckInState)
                    ? "Both checked in"
                    : "Waiting"}
                </span>
              </div>

              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {[
                  {
                    side: "home" as const,
                    label: selectedGame.homeTeamName,
                  },
                  {
                    side: "away" as const,
                    label: selectedGame.awayTeamName,
                  },
                ].map(({ side, label }) => {
                  const checkedIn = teamCheckInState[side];

                  return (
                    <div
                      key={side}
                      className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            {side}
                          </div>
                          <div className="mt-1 font-semibold text-slate-200">
                            {label}
                          </div>
                        </div>

                        <span
                          className={
                            checkedIn
                              ? "text-sm font-semibold text-emerald-400"
                              : "text-sm font-semibold text-slate-500"
                          }
                        >
                          {checkedIn ? "Checked in" : "Not checked in"}
                        </span>
                      </div>

                      <button
                        type="button"
                        data-testid={`team-check-in-${side}`}
                        onClick={() =>
                          updateTeamCheckIn(side, !checkedIn)
                        }
                        className="mt-4 w-full rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900"
                      >
                        {checkedIn
                          ? "Undo check-in"
                          : "Mark checked in"}
                      </button>
                    </div>
                  );
                })}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Check-in is stored per game for local operations testing.
                Testing override may bypass readiness, but it does not alter
                either team's actual check-in state.
              </p>
            </section>

            <section
              data-testid="roster-lock-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Roster locking
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Freeze each team's game roster after check-in.
                  </p>
                </div>

                <span
                  className={
                    areBothRostersLocked(rosterLockState)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {areBothRostersLocked(rosterLockState)
                    ? "Both locked"
                    : "Pending"}
                </span>
              </div>

              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {[
                  {
                    side: "home" as const,
                    label: selectedGame.homeTeamName,
                  },
                  {
                    side: "away" as const,
                    label: selectedGame.awayTeamName,
                  },
                ].map(({ side, label }) => {
                  const locked = rosterLockState[side];
                  const checkedIn = teamCheckInState[side];
                  const lockAllowed = canLockRoster(
                    checkedIn,
                    testingOverrideEnabled,
                  );

                  return (
                    <div
                      key={side}
                      className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            {side}
                          </div>
                          <div className="mt-1 font-semibold text-slate-200">
                            {label}
                          </div>
                          <div className="mt-1 text-xs text-slate-500">
                            {checkedIn
                              ? "Team checked in"
                              : testingOverrideEnabled
                                ? "Check-in bypassed by testing override"
                                : "Check-in required before locking"}
                          </div>
                        </div>

                        <span
                          className={
                            locked
                              ? "text-sm font-semibold text-emerald-400"
                              : "text-sm font-semibold text-slate-500"
                          }
                        >
                          {locked ? "Locked" : "Unlocked"}
                        </span>
                      </div>

                      <button
                        type="button"
                        data-testid={`roster-lock-${side}`}
                        disabled={!locked && !lockAllowed}
                        onClick={() =>
                          updateRosterLock(side, !locked)
                        }
                        className="mt-4 w-full rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900 disabled:cursor-not-allowed disabled:opacity-40"
                      >
                        {locked ? "Unlock roster" : "Lock roster"}
                      </button>
                    </div>
                  );
                })}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Roster locks are per-game operational state in Milestone 7.4.
                Testing override may bypass the prerequisite check-in gate but
                does not silently mark the roster as locked.
              </p>
            </section>

            <section
              data-testid="officials-assignment-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Officials assignment
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Assign the on-ice crew for this game.
                  </p>
                </div>

                <span
                  className={
                    hasRequiredOfficials(officialsAssignment)
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {hasCompleteOfficialsCrew(officialsAssignment)
                    ? "Crew complete"
                    : hasRequiredOfficials(officialsAssignment)
                      ? "Required officials ready"
                      : "Assignment incomplete"}
                </span>
              </div>

              <div className="mt-4 grid gap-3 md:grid-cols-2">
                {[
                  {
                    field: "referee1" as const,
                    label: "Referee 1",
                    required: true,
                  },
                  {
                    field: "referee2" as const,
                    label: "Referee 2",
                    required: true,
                  },
                  {
                    field: "linesman1" as const,
                    label: "Linesman 1",
                    required: false,
                  },
                  {
                    field: "linesman2" as const,
                    label: "Linesman 2",
                    required: false,
                  },
                ].map(({ field, label, required }) => (
                  <label
                    key={field}
                    className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-semibold text-slate-200">
                        {label}
                      </span>
                      <span className="text-[10px] uppercase tracking-wide text-slate-500">
                        {required ? "required" : "optional"}
                      </span>
                    </div>

                    <input
                      type="text"
                      data-testid={`official-${field}`}
                      value={officialsAssignment[field]}
                      onChange={(event) =>
                        updateOfficialAssignment(
                          field,
                          event.target.value,
                        )
                      }
                      placeholder="Official name"
                      className="mt-3 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-slate-500"
                    />
                  </label>
                ))}
              </div>

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Milestone 7.5 treats two assigned referees as the required
                readiness threshold. Linesmen remain visible as optional crew
                positions until tournament rules make them mandatory.
              </p>
            </section>

            <section
              data-testid="game-start-authorization-panel"
              className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Game start authorization
                  </h2>
                  <p className="mt-1 text-xs leading-5 text-slate-500">
                    Record operator approval after readiness review. This
                    authorization does not itself transition the game to LIVE.
                  </p>
                </div>

                <span
                  data-testid="game-start-authorization-status"
                  className={
                    gameStartAuthorization
                      ? "text-sm font-semibold text-emerald-400"
                      : "text-sm font-semibold text-amber-400"
                  }
                >
                  {gameStartAuthorization
                    ? "Authorized"
                    : "Not authorized"}
                </span>
              </div>

              {gameStartAuthorization ? (
                <div className="mt-4 rounded-lg border border-emerald-900/70 bg-emerald-950/20 p-4">
                  <div className="grid gap-2 text-sm md:grid-cols-2">
                    <div>
                      <span className="text-slate-500">Authorized by</span>
                      <div className="font-semibold text-slate-200">
                        {gameStartAuthorization.authorizedBy}
                      </div>
                    </div>
                    <div>
                      <span className="text-slate-500">Mode</span>
                      <div className="font-semibold text-slate-200">
                        {gameStartAuthorization.mode === "normal"
                          ? "Normal readiness"
                          : "Testing override"}
                      </div>
                    </div>
                  </div>

                  {gameStartAuthorization.mode === "testing-override" ? (
                    <div className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-xs text-amber-300">
                      Actual readiness was BLOCKED when authorization was
                      recorded. Reason:{" "}
                      {gameStartAuthorization.overrideReason}
                    </div>
                  ) : null}

                  <button
                    type="button"
                    data-testid="revoke-game-start-authorization"
                    onClick={revokeGameStartAuthorization}
                    className="mt-4 rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-900"
                  >
                    Revoke authorization
                  </button>
                </div>
              ) : (
                <div className="mt-4 space-y-3">
                  <label className="block">
                    <span className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Authorizing operator
                    </span>
                    <input
                      type="text"
                      data-testid="game-start-authorization-operator"
                      value={authorizationOperator}
                      onChange={(event) =>
                        setAuthorizationOperator(event.target.value)
                      }
                      placeholder="Operator name"
                      className="mt-2 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-slate-500"
                    />
                  </label>

                  {!pregameReadinessSummary?.actualReady &&
                  testingOverrideEnabled ? (
                    <label className="block">
                      <span className="text-xs font-semibold uppercase tracking-wide text-amber-400">
                        Testing override reason
                      </span>
                      <input
                        type="text"
                        data-testid="game-start-authorization-override-reason"
                        value={authorizationOverrideReason}
                        onChange={(event) =>
                          setAuthorizationOverrideReason(event.target.value)
                        }
                        placeholder="Why is the readiness gate being bypassed?"
                        className="mt-2 w-full rounded-lg border border-amber-800/60 bg-slate-950 px-3 py-2 text-sm text-slate-100 outline-none transition focus:border-amber-500"
                      />
                    </label>
                  ) : null}

                  <button
                    type="button"
                    data-testid="authorize-game-start"
                    disabled={
                      !pregameReadinessSummary ||
                      !canAuthorizeGameStart({
                        authorizedBy: authorizationOperator,
                        actualReady:
                          pregameReadinessSummary.actualReady,
                        effectiveReady:
                          pregameReadinessSummary.effectiveReady,
                        testingOverrideEnabled,
                        overrideReason:
                          authorizationOverrideReason,
                      })
                    }
                    onClick={authorizeGameStart}
                    className="w-full rounded-lg border border-emerald-800/70 bg-emerald-950/20 px-3 py-2 text-sm font-semibold text-emerald-300 transition hover:border-emerald-600 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Authorize game start
                  </button>
                </div>
              )}

              <p className="mt-3 text-xs leading-5 text-slate-500">
                Security boundary: this browser-side authorization is an
                operations record only. Milestone 7.7 will require an
                authenticated server-side transition before a game can become
                LIVE; local testing override state will never be accepted as
                server authority.
              </p>
            </section>

            <GameLiveTransitionControl
              gameId={selectedGame.id}
              scheduledStart={selectedGame.scheduledStart}
              authorization={gameStartAuthorization}
            />

            <GameResultFinalizationControl
              gameId={selectedGame.id}
            />

<aside className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <h2 className="font-semibold text-slate-100">
                    Pregame readiness
                  </h2>
                  <p className="mt-1 text-xs text-slate-500">
                    Actual vs effective readiness
                  </p>
                </div>
                <span
                  data-testid="game-operations-readiness-count"
                  className="text-sm font-semibold text-slate-300"
                >
                  {pregameReadinessSummary?.effectiveReady ? "READY" : "BLOCKED"}
                </span>
              </div>

              <div className="mt-4 space-y-2">
                {pregameReadinessSummary?.checks.map((check) => (
                  <PregameReadinessRow key={check.id} check={check} />
                ))}
              </div>

              <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                <div className="rounded-lg border border-slate-800 px-3 py-2">
                  <span className="text-slate-500">Actual</span>
                  <div
                    data-testid="pregame-actual-readiness"
                    className={
                      pregameReadinessSummary?.actualReady
                        ? "mt-1 font-semibold text-emerald-400"
                        : "mt-1 font-semibold text-red-400"
                    }
                  >
                    {pregameReadinessSummary?.actualReady
                      ? "READY"
                      : "BLOCKED"}
                  </div>
                </div>

                <div className="rounded-lg border border-slate-800 px-3 py-2">
                  <span className="text-slate-500">Effective</span>
                  <div
                    data-testid="pregame-effective-readiness"
                    className={
                      pregameReadinessSummary?.effectiveReady
                        ? "mt-1 font-semibold text-emerald-400"
                        : "mt-1 font-semibold text-red-400"
                    }
                  >
                    {pregameReadinessSummary?.effectiveReady
                      ? "READY"
                      : "BLOCKED"}
                  </div>
                </div>
              </div>

              {pregameReadinessSummary?.testingOverrideApplied ? (
                <p
                  data-testid="pregame-testing-override-applied"
                  className="mt-3 rounded-lg border border-amber-800/60 bg-amber-950/20 px-3 py-2 text-xs font-semibold text-amber-300"
                >
                  Testing override is bypassing one or more required readiness
                  failures. Actual readiness remains BLOCKED.
                </p>
              ) : null}

              <p className="mt-4 text-xs leading-5 text-slate-500">
                Actual game data is never changed by testing override. Later
                Milestone 7 readiness gates will consume the same local testing
                override so incomplete setup can be bypassed during development
                while the real readiness state remains visible.
              </p>
            </aside>
          </div>

          <div>
            <h2 className="text-lg font-semibold text-slate-100">
              Operator actions
            </h2>
            <p className="mt-1 text-sm text-slate-400">
              Action surfaces are visible now so the workspace structure is
              stable, but mutations remain disabled until their owning
              milestones implement authorization, validation, and auditing.
            </p>

            <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              <FutureAction
                title="Pregame readiness"
                milestone="7.2"
                description="Roster, scoreboard, scoring operator, stream, and required-condition checks."
              />
              <FutureAction
                title="Team check-in"
                milestone="7.3"
                description="Track home and away arrival and readiness."
              />
              <FutureAction
                title="Roster & officials"
                milestone="7.4–7.5"
                description="Lock active rosters and assign game officials."
              />
              <FutureAction
                title="Authorize game start"
                milestone="7.6"
                description="Gate transition to LIVE behind readiness or an audited override."
              />
            </div>
          </div>
        </>
      )}
    </section>
  );
}
