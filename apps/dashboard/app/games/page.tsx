"use client";

import Link from "next/link";
import { io } from "socket.io-client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { GameScoringConsole, type ScoringAction } from "../../components/games/GameScoringConsole";
import { API, api } from "../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
} from "../../lib/auth";
import { AMERICAS_TIME_ZONES } from "../../lib/timezones";

type Organization = { id: number; name: string };
type Season = { id: number; organizationId: number; name: string };
type TeamOption = {
  id: number;
  organizationId: number;
  organizationName: string;
  name: string;
};
type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";
type GamePhase = "PREGAME" | "REGULATION" | "INTERMISSION" | "OVERTIME" | "FINAL";

type Game = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonId: number;
  seasonName: string;
  homeTeamId: number | null;
  homeTeamName: string;
  homeTeamOrganizationName: string | null;
  homeExternalName: string | null;
  awayTeamId: number | null;
  awayTeamName: string;
  awayTeamOrganizationName: string | null;
  awayExternalName: string | null;
  scheduledStart: string;
  timezone: string;
  venue: string | null;
  status: GameStatus;
  gamePhase: GamePhase;
  homeScore: number;
  awayScore: number;
  period: number;
  periodLengthMs: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
  regulationPeriods: number;
  regulationPeriodLengthMs: number;
  intermissionLengthMs: number;
  intermissionRemainingMs: number;
  intermissionRunning: boolean;
  intermissionStartedAt: string | null;
  intermissionReady: boolean;
  overtimeEnabled: boolean;
  overtimeLengthMs: number;
  periodLabel: string;
  canAdvancePeriod: boolean;
  notes: string | null;
};

type Form = {
  organizationId: number;
  seasonId: number;
  homeTeamId: number | null;
  homeExternalName: string;
  awayTeamId: number | null;
  awayExternalName: string;
  scheduledStart: string;
  timezone: string;
  venue: string;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  regulationPeriods: number;
  regulationPeriodLengthMinutes: number;
  intermissionLengthMinutes: number;
  overtimeEnabled: boolean;
  overtimeLengthMinutes: number;
  notes: string;
};

type RulesPreset = "CUSTOM" | "YOUTH" | "HIGH_SCHOOL" | "COLLEGE";

const RULE_PRESETS: Record<
  Exclude<RulesPreset, "CUSTOM">,
  Pick<
    Form,
    | "regulationPeriods"
    | "regulationPeriodLengthMinutes"
    | "intermissionLengthMinutes"
    | "overtimeEnabled"
    | "overtimeLengthMinutes"
  >
> = {
  YOUTH: {
    regulationPeriods: 3,
    regulationPeriodLengthMinutes: 15,
    intermissionLengthMinutes: 10,
    overtimeEnabled: true,
    overtimeLengthMinutes: 5,
  },
  HIGH_SCHOOL: {
    regulationPeriods: 3,
    regulationPeriodLengthMinutes: 17,
    intermissionLengthMinutes: 15,
    overtimeEnabled: true,
    overtimeLengthMinutes: 8,
  },
  COLLEGE: {
    regulationPeriods: 3,
    regulationPeriodLengthMinutes: 20,
    intermissionLengthMinutes: 15,
    overtimeEnabled: true,
    overtimeLengthMinutes: 5,
  },
};

const statuses: readonly GameStatus[] = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"];

const blank: Form = {
  organizationId: 0,
  seasonId: 0,
  homeTeamId: null,
  homeExternalName: "",
  awayTeamId: null,
  awayExternalName: "",
  scheduledStart: "",
  timezone: "America/Chicago",
  venue: "",
  status: "SCHEDULED",
  homeScore: 0,
  awayScore: 0,
  regulationPeriods: 3,
  regulationPeriodLengthMinutes: 20,
  intermissionLengthMinutes: 15,
  overtimeEnabled: true,
  overtimeLengthMinutes: 5,
  notes: "",
};

function toLocalDateTime(isoValue: string): string {
  const date = new Date(isoValue);
  const offsetMilliseconds = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offsetMilliseconds).toISOString().slice(0, 16);
}

function statusClassName(status: GameStatus): string {
  return status === "LIVE" || status === "FINAL" ? "badge" : "badge off";
}

export default function GamesPage() {
  const [currentUser, setCurrentUser] = useState<AuthenticatedUser | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [seasons, setSeasons] = useState<Season[]>([]);
  const [teamOptions, setTeamOptions] = useState<TeamOption[]>([]);
  const [games, setGames] = useState<Game[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [organizationFilter, setOrganizationFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [scoringGameId, setScoringGameId] = useState<number | null>(null);
  const [scoringBusy, setScoringBusy] = useState(false);
  const [scoringError, setScoringError] = useState("");
  const [rulesPreset, setRulesPreset] = useState<RulesPreset>("COLLEGE");

  const canManage = userHasPermission(currentUser, PERMISSIONS.GAME_MANAGE);
  const canScore = userHasPermission(currentUser, PERMISSIONS.GAME_SCORE);
  const isSystemAdmin = currentUser?.role === "system_admin";

  const organizationSeasons = useMemo(
    () => seasons.filter((season) => season.organizationId === form.organizationId),
    [seasons, form.organizationId],
  );

  const filteredGames = useMemo(
    () =>
      games.filter((game) => {
        const text = `${game.homeTeamName} ${game.awayTeamName} ${game.venue ?? ""}`.toLowerCase();

        return (
          (!organizationFilter || game.organizationId === Number(organizationFilter)) &&
          (!statusFilter || game.status === statusFilter) &&
          text.includes(search.trim().toLowerCase())
        );
      }),
    [games, organizationFilter, statusFilter, search],
  );

  const scoringGame = games.find((game) => game.id === scoringGameId) ?? null;

  const load = useCallback(async () => {
    try {
      const [organizationResponse, seasonResponse, teamResponse, gameResponse] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ seasons: Season[] }>("/seasons"),
        api<{ teams: TeamOption[] }>("/games/team-options"),
        api<{ games: Game[] }>("/games"),
      ]);

      setOrganizations(organizationResponse.organizations);
      setSeasons(seasonResponse.seasons);
      setTeamOptions(teamResponse.teams);
      setGames(gameResponse.games);

      setForm((current) =>
        current.organizationId
          ? current
          : {
              ...current,
              organizationId: organizationResponse.organizations[0]?.id ?? 0,
            },
      );
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load games");
    }
  }, []);

  useEffect(() => setCurrentUser(getStoredUser()), []);

  useEffect(() => {
    void load();
    const socket = io(API);
    let connectedOnce = false;

    socket.on("connect", () => {
      if (!connectedOnce) {
        connectedOnce = true;
        return;
      }

      void load();
    });

    [
      "game:created",
      "game:updated",
      "game:deleted",
      "game:scored",
      "game:clock-expired",
      "game:intermission-expired",
    ].forEach((eventName) => socket.on(eventName, load));
    return () => {
      socket.disconnect();
    };
  }, [load]);

  useEffect(() => {
    if (!form.organizationId) return;

    setForm((current) => ({
      ...current,
      seasonId: organizationSeasons.some((season) => season.id === current.seasonId)
        ? current.seasonId
        : (organizationSeasons[0]?.id ?? 0),
    }));
  }, [form.organizationId, organizationSeasons]);

  function applyRulesPreset(preset: RulesPreset): void {
    setRulesPreset(preset);

    if (preset === "CUSTOM") return;

    setForm((current) => ({
      ...current,
      ...RULE_PRESETS[preset],
    }));
  }

  function reset(): void {
    setEditing(null);
    setError("");
    setRulesPreset("COLLEGE");
    setRulesPreset("COLLEGE");
    setForm({
      ...blank,
      organizationId: organizations[0]?.id ?? 0,
    });
  }

  function edit(game: Game): void {
    if (!canManage) return;

    setEditing(game.id);
    setRulesPreset("CUSTOM");
    setForm({
      organizationId: game.organizationId,
      seasonId: game.seasonId,
      homeTeamId: game.homeTeamId,
      homeExternalName: game.homeExternalName ?? "",
      awayTeamId: game.awayTeamId,
      awayExternalName: game.awayExternalName ?? "",
      scheduledStart: toLocalDateTime(game.scheduledStart),
      timezone: game.timezone,
      venue: game.venue ?? "",
      status: game.status,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
      regulationPeriods: game.regulationPeriods,
      regulationPeriodLengthMinutes: game.regulationPeriodLengthMs / 60_000,
      intermissionLengthMinutes: game.intermissionLengthMs / 60_000,
      overtimeEnabled: game.overtimeEnabled,
      overtimeLengthMinutes: game.overtimeLengthMs / 60_000,
      notes: game.notes ?? "",
    });

    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function save(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    if (!canManage) {
      setError("You do not have permission to manage games.");
      return;
    }

    if (!form.scheduledStart) {
      setError("Scheduled start is required.");
      return;
    }

    if (!form.homeTeamId && !form.homeExternalName.trim()) {
      setError("Select or enter a home team.");
      return;
    }

    if (!form.awayTeamId && !form.awayExternalName.trim()) {
      setError("Select or enter an away team.");
      return;
    }

    if (form.homeTeamId && form.awayTeamId && form.homeTeamId === form.awayTeamId) {
      setError("Home and away teams must be different.");
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api(editing ? `/games/${editing}` : "/games", {
        method: editing ? "PUT" : "POST",
        body: JSON.stringify({
          ...form,
          homeExternalName: form.homeTeamId ? null : form.homeExternalName.trim() || null,
          awayExternalName: form.awayTeamId ? null : form.awayExternalName.trim() || null,
          scheduledStart: new Date(form.scheduledStart).toISOString(),
          regulationPeriodLengthMs: Math.round(form.regulationPeriodLengthMinutes * 60_000),
          intermissionLengthMs: Math.round(form.intermissionLengthMinutes * 60_000),
          overtimeLengthMs: Math.round(form.overtimeLengthMinutes * 60_000),
          venue: form.venue || null,
          notes: form.notes || null,
        }),
      });

      reset();
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not save game");
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number): Promise<void> {
    if (!canManage || !window.confirm("Delete this game?")) return;

    try {
      await api(`/games/${id}`, { method: "DELETE" });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not delete game");
    }
  }

  async function score(gameId: number, action: ScoringAction): Promise<void> {
    if (!canScore || scoringBusy) return;

    setScoringBusy(true);
    setScoringError("");

    const actionId = crypto.randomUUID();

    try {
      const response = await api<{ game: Game }>(`/games/${gameId}/scoring`, {
        method: "POST",
        body: JSON.stringify({ ...action, actionId }),
      });

      setGames((current) =>
        current.map((game) => (game.id === response.game.id ? response.game : game)),
      );
    } catch (cause) {
      setScoringError(cause instanceof Error ? cause.message : "Could not update game");
    } finally {
      setScoringBusy(false);
    }
  }

  function sideFields(side: "home" | "away") {
    const teamId = side === "home" ? form.homeTeamId : form.awayTeamId;
    const externalName = side === "home" ? form.homeExternalName : form.awayExternalName;

    return (
      <>
        <label>
          {side === "home" ? "Home team" : "Away team"}
          <select
            value={teamId ?? "external"}
            onChange={(event) => {
              const external = event.target.value === "external";
              setForm({
                ...form,
                [`${side}TeamId`]: external ? null : Number(event.target.value),
                [`${side}ExternalName`]: external ? externalName : "",
              });
            }}
          >
            <option value="external">External opponent</option>
            {teamOptions
              .filter((team) => team.id !== (side === "home" ? form.awayTeamId : form.homeTeamId))
              .map((team) => (
                <option key={team.id} value={team.id}>
                  {team.organizationName} · {team.name}
                </option>
              ))}
          </select>
        </label>

        {!teamId && (
          <label>
            {side === "home" ? "External home name" : "External away name"}
            <input
              required
              maxLength={160}
              value={externalName}
              onChange={(event) =>
                setForm({
                  ...form,
                  [`${side}ExternalName`]: event.target.value,
                })
              }
              placeholder="Example: Lakeville North"
            />
          </label>
        )}
      </>
    );
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Games</h1>
            <p className="muted">
              Schedule registered teams across organizations or enter an external opponent.
            </p>
          </div>

          <div className="filters">
            {isSystemAdmin && organizations.length > 1 && (
              <select
                value={organizationFilter}
                onChange={(event) => setOrganizationFilter(event.target.value)}
              >
                <option value="">All managing organizations</option>
                {organizations.map((organization) => (
                  <option key={organization.id} value={organization.id}>
                    {organization.name}
                  </option>
                ))}
              </select>
            )}

            <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
              <option value="">All statuses</option>
              {statuses.map((status) => (
                <option key={status} value={status}>
                  {status}
                </option>
              ))}
            </select>

            <input
              className="search"
              placeholder="Search games"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
        </div>

        {canManage && (
          <section className="panel">
            <h2>{editing ? "Edit game" : "Add game"}</h2>

            {!organizations.length ? (
              <p>Create a managing organization first.</p>
            ) : !organizationSeasons.length ? (
              <p>Create a season for the managing organization first.</p>
            ) : (
              <form className="formGrid" onSubmit={save}>
                <label>
                  Managing organization
                  <select
                    required
                    disabled={!isSystemAdmin}
                    value={form.organizationId}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        organizationId: Number(event.target.value),
                        seasonId: 0,
                      })
                    }
                  >
                    {organizations.map((organization) => (
                      <option key={organization.id} value={organization.id}>
                        {organization.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Season
                  <select
                    required
                    value={form.seasonId}
                    onChange={(event) => setForm({ ...form, seasonId: Number(event.target.value) })}
                  >
                    <option value={0}>Select season</option>
                    {organizationSeasons.map((season) => (
                      <option key={season.id} value={season.id}>
                        {season.name}
                      </option>
                    ))}
                  </select>
                </label>

                {sideFields("home")}
                {sideFields("away")}

                <label>
                  Scheduled start
                  <input
                    required
                    type="datetime-local"
                    value={form.scheduledStart}
                    onChange={(event) => setForm({ ...form, scheduledStart: event.target.value })}
                  />
                </label>

                <label>
                  Timezone
                  <select
                    required
                    value={form.timezone}
                    onChange={(event) => setForm({ ...form, timezone: event.target.value })}
                  >
                    {AMERICAS_TIME_ZONES.map((timezone) => (
                      <option key={timezone} value={timezone}>
                        {timezone.replaceAll("_", " ")}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Venue
                  <input
                    value={form.venue}
                    onChange={(event) => setForm({ ...form, venue: event.target.value })}
                  />
                </label>

                <label>
                  Status
                  <select
                    value={form.status}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        status: event.target.value as GameStatus,
                      })
                    }
                  >
                    {statuses.map((status) => (
                      <option key={status} value={status}>
                        {status}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Home score
                  <input
                    type="number"
                    min="0"
                    max="999"
                    value={form.homeScore}
                    onChange={(event) =>
                      setForm({ ...form, homeScore: Number(event.target.value) })
                    }
                  />
                </label>

                <label>
                  Away score
                  <input
                    type="number"
                    min="0"
                    max="999"
                    value={form.awayScore}
                    onChange={(event) =>
                      setForm({ ...form, awayScore: Number(event.target.value) })
                    }
                  />
                </label>

                <div
                  style={{
                    gridColumn: "1 / -1",
                    padding: "18px",
                    border: "1px solid #334155",
                    borderRadius: "16px",
                    background: "rgba(15, 23, 42, 0.55)",
                  }}
                >
                  <h3 style={{ marginTop: 0 }}>Game rules</h3>

                  <div className="formGrid">
                    <label>
                      Game rules preset
                      <select
                        value={rulesPreset}
                        onChange={(event) => applyRulesPreset(event.target.value as RulesPreset)}
                      >
                        <option value="YOUTH">Youth hockey</option>
                        <option value="HIGH_SCHOOL">High school</option>
                        <option value="COLLEGE">College / standard</option>
                        <option value="CUSTOM">Custom</option>
                      </select>
                    </label>

                    <label>
                      Regulation periods
                      <input
                        type="number"
                        min="1"
                        max="10"
                        value={form.regulationPeriods}
                        onChange={(event) => {
                          setRulesPreset("CUSTOM");
                          setForm({
                            ...form,
                            regulationPeriods: Number(event.target.value),
                          });
                        }}
                      />
                    </label>

                    <label>
                      Period length (minutes)
                      <input
                        type="number"
                        min="1"
                        max="120"
                        step="0.5"
                        value={form.regulationPeriodLengthMinutes}
                        onChange={(event) => {
                          setRulesPreset("CUSTOM");
                          setForm({
                            ...form,
                            regulationPeriodLengthMinutes: Number(event.target.value),
                          });
                        }}
                      />
                    </label>

                    <label>
                      Intermission (minutes)
                      <input
                        type="number"
                        min="0"
                        max="60"
                        step="0.5"
                        value={form.intermissionLengthMinutes}
                        onChange={(event) => {
                          setRulesPreset("CUSTOM");
                          setForm({
                            ...form,
                            intermissionLengthMinutes: Number(event.target.value),
                          });
                        }}
                      />
                    </label>

                    <label className="check">
                      <input
                        type="checkbox"
                        checked={form.overtimeEnabled}
                        onChange={(event) => {
                          setRulesPreset("CUSTOM");
                          setForm({
                            ...form,
                            overtimeEnabled: event.target.checked,
                          });
                        }}
                      />
                      Overtime enabled
                    </label>

                    {form.overtimeEnabled && (
                      <label>
                        Overtime length (minutes)
                        <input
                          type="number"
                          min="1"
                          max="60"
                          step="0.5"
                          value={form.overtimeLengthMinutes}
                          onChange={(event) => {
                            setRulesPreset("CUSTOM");
                            setForm({
                              ...form,
                              overtimeLengthMinutes: Number(event.target.value),
                            });
                          }}
                        />
                      </label>
                    )}
                  </div>

                  {editing && games.find((entry) => entry.id === editing)?.status === "LIVE" && (
                    <p className="muted">
                      Saving these rules will not reset the live game clock. Use the scoring
                      controller to change the current clock.
                    </p>
                  )}
                </div>

                <label>
                  Notes
                  <textarea
                    value={form.notes}
                    onChange={(event) => setForm({ ...form, notes: event.target.value })}
                  />
                </label>

                <div className="formActions">
                  <button disabled={busy}>
                    {busy ? "Saving…" : editing ? "Save changes" : "Create game"}
                  </button>
                  {editing && (
                    <button type="button" className="secondary" onClick={reset}>
                      Cancel
                    </button>
                  )}
                </div>
              </form>
            )}
          </section>
        )}

        {error && <p className="error">{error}</p>}

        <div className="entityGrid">
          {filteredGames.map((game) => (
            <article className="entityCard" key={game.id}>
              <div>
                <h3>
                  {game.awayTeamName} at {game.homeTeamName}
                </h3>
                <p>Managed by {game.organizationName}</p>
              </div>

              <div className="entityStats">
                <b>
                  {game.awayScore} – {game.homeScore}
                </b>
                <span className={statusClassName(game.status)}>{game.status}</span>
              </div>

              <p>
                {new Date(game.scheduledStart).toLocaleString()} · {game.seasonName}
              </p>
              <p>{game.venue || "Venue not set"}</p>
              <p>
                {game.regulationPeriods} × {game.regulationPeriodLengthMs / 60_000} min periods ·{" "}
                {game.intermissionLengthMs / 60_000} min intermission ·{" "}
                {game.overtimeEnabled
                  ? `${game.overtimeLengthMs / 60_000} min overtime`
                  : "No overtime"}
              </p>
              {game.notes && <p>{game.notes}</p>}

              <div className="cardActions">
                <Link
                  className="secondary"
                  href={`/games/${game.id}/scoreboard`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Open scoreboard
                </Link>

                {canScore && (
                  <button
                    onClick={() => {
                      setScoringError("");
                      setScoringGameId(game.id);
                    }}
                  >
                    Score game
                  </button>
                )}

                {canManage && (
                  <>
                    <button className="secondary" onClick={() => edit(game)}>
                      Edit
                    </button>
                    <button className="danger" onClick={() => void remove(game.id)}>
                      Delete
                    </button>
                  </>
                )}
              </div>
            </article>
          ))}
        </div>

        {!filteredGames.length && (
          <section className="panel">
            <p>No games match the current filters.</p>
          </section>
        )}

        {scoringGame && canScore && (
          <GameScoringConsole
            game={scoringGame}
            busy={scoringBusy}
            error={scoringError}
            onAction={(action) => score(scoringGame.id, action)}
            onClose={() => {
              setScoringError("");
              setScoringGameId(null);
            }}
          />
        )}
      </AppShell>
    </AuthGate>
  );
}
