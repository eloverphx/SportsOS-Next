"use client";

import { io } from "socket.io-client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
} from "../../lib/auth";
import { AMERICAS_TIME_ZONES } from "../../lib/timezones";

type Organization = {
  id: number;
  name: string;
};

type Season = {
  id: number;
  organizationId: number;
  name: string;
};

type Team = {
  id: number;
  organizationId: number;
  name: string;
};

type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type Game = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonId: number;
  seasonName: string;
  homeTeamId: number;
  homeTeamName: string;
  awayTeamId: number;
  awayTeamName: string;
  scheduledStart: string;
  timezone: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  notes: string | null;
};

type Form = {
  organizationId: number;
  seasonId: number;
  homeTeamId: number;
  awayTeamId: number;
  scheduledStart: string;
  timezone: string;
  venue: string;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  notes: string;
};

const statuses: readonly GameStatus[] = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"];

const blank: Form = {
  organizationId: 0,
  seasonId: 0,
  homeTeamId: 0,
  awayTeamId: 0,
  scheduledStart: "",
  timezone: "America/Chicago",
  venue: "",
  status: "SCHEDULED",
  homeScore: 0,
  awayScore: 0,
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
  const [teams, setTeams] = useState<Team[]>([]);
  const [games, setGames] = useState<Game[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [organizationFilter, setOrganizationFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const canManage = userHasPermission(currentUser, PERMISSIONS.GAME_MANAGE);

  const isSystemAdmin = currentUser?.role === "system_admin";

  const organizationSeasons = useMemo(
    () => seasons.filter((season) => season.organizationId === form.organizationId),
    [seasons, form.organizationId],
  );

  const organizationTeams = useMemo(
    () => teams.filter((team) => team.organizationId === form.organizationId),
    [teams, form.organizationId],
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

  const load = useCallback(async () => {
    try {
      const [organizationResponse, seasonResponse, teamResponse, gameResponse] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ seasons: Season[] }>("/seasons"),
        api<{ teams: Team[] }>("/teams"),
        api<{ games: Game[] }>("/games"),
      ]);

      setOrganizations(organizationResponse.organizations);
      setSeasons(seasonResponse.seasons);
      setTeams(teamResponse.teams);
      setGames(gameResponse.games);

      setForm((current) =>
        current.organizationId
          ? current
          : {
              ...current,
              organizationId: organizationResponse.organizations[0]?.id ?? 0,
            },
      );
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load games");
    }
  }, []);

  useEffect(() => {
    setCurrentUser(getStoredUser());
  }, []);

  useEffect(() => {
    void load();

    const socket = io(API);

    ["game:created", "game:updated", "game:deleted"].forEach((eventName) =>
      socket.on(eventName, load),
    );

    return () => {
      socket.disconnect();
    };
  }, [load]);

  useEffect(() => {
    if (!form.organizationId) {
      return;
    }

    const firstSeasonId = organizationSeasons[0]?.id ?? 0;
    const firstTeamId = organizationTeams[0]?.id ?? 0;
    const secondTeamId = organizationTeams.find((team) => team.id !== firstTeamId)?.id ?? 0;

    setForm((current) => {
      const homeTeamId = organizationTeams.some((team) => team.id === current.homeTeamId)
        ? current.homeTeamId
        : firstTeamId;

      return {
        ...current,
        seasonId: organizationSeasons.some((season) => season.id === current.seasonId)
          ? current.seasonId
          : firstSeasonId,
        homeTeamId,
        awayTeamId:
          organizationTeams.some((team) => team.id === current.awayTeamId) &&
          current.awayTeamId !== homeTeamId
            ? current.awayTeamId
            : (organizationTeams.find((team) => team.id !== homeTeamId)?.id ?? secondTeamId),
      };
    });
  }, [form.organizationId, organizationSeasons, organizationTeams]);

  function reset(): void {
    setEditing(null);
    setError("");
    setForm({
      ...blank,
      organizationId: organizations[0]?.id ?? 0,
    });
  }

  function edit(game: Game): void {
    if (!canManage) {
      return;
    }

    setEditing(game.id);
    setForm({
      organizationId: game.organizationId,
      seasonId: game.seasonId,
      homeTeamId: game.homeTeamId,
      awayTeamId: game.awayTeamId,
      scheduledStart: toLocalDateTime(game.scheduledStart),
      timezone: game.timezone,
      venue: game.venue ?? "",
      status: game.status,
      homeScore: game.homeScore,
      awayScore: game.awayScore,
      notes: game.notes ?? "",
    });

    window.scrollTo({
      top: 0,
      behavior: "smooth",
    });
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

    if (form.homeTeamId === form.awayTeamId) {
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
          scheduledStart: new Date(form.scheduledStart).toISOString(),
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
    if (!canManage) {
      setError("You do not have permission to manage games.");
      return;
    }

    if (!window.confirm("Delete this game?")) {
      return;
    }

    try {
      await api(`/games/${id}`, {
        method: "DELETE",
      });

      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not delete game");
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Games</h1>
            <p className="muted">Schedule matchups and maintain game status and scores.</p>
          </div>

          <div className="filters">
            {isSystemAdmin && organizations.length > 1 && (
              <select
                value={organizationFilter}
                onChange={(event) => setOrganizationFilter(event.target.value)}
              >
                <option value="">All organizations</option>

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

        {!canManage && (
          <section className="panel">
            <h2>Game schedule</h2>
            <p className="muted">Your account has read-only access to games.</p>
          </section>
        )}

        {canManage && (
          <section className="panel">
            <h2>{editing ? "Edit game" : "Add game"}</h2>

            {!organizations.length ? (
              <p>Create an organization first.</p>
            ) : organizationTeams.length < 2 ? (
              <p>
                Create at least two teams in the selected organization before scheduling a game.
              </p>
            ) : !organizationSeasons.length ? (
              <p>Create a season in the selected organization before scheduling a game.</p>
            ) : (
              <form className="formGrid" onSubmit={save}>
                <label>
                  Organization
                  <select
                    required
                    disabled={!isSystemAdmin}
                    value={form.organizationId}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        organizationId: Number(event.target.value),
                        seasonId: 0,
                        homeTeamId: 0,
                        awayTeamId: 0,
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
                    onChange={(event) =>
                      setForm({
                        ...form,
                        seasonId: Number(event.target.value),
                      })
                    }
                  >
                    <option value={0}>Select season</option>

                    {organizationSeasons.map((season) => (
                      <option key={season.id} value={season.id}>
                        {season.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Home team
                  <select
                    required
                    value={form.homeTeamId}
                    onChange={(event) => {
                      const homeTeamId = Number(event.target.value);

                      setForm({
                        ...form,
                        homeTeamId,
                        awayTeamId:
                          form.awayTeamId === homeTeamId
                            ? (organizationTeams.find((team) => team.id !== homeTeamId)?.id ?? 0)
                            : form.awayTeamId,
                      });
                    }}
                  >
                    <option value={0}>Select team</option>

                    {organizationTeams.map((team) => (
                      <option key={team.id} value={team.id}>
                        {team.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Away team
                  <select
                    required
                    value={form.awayTeamId}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        awayTeamId: Number(event.target.value),
                      })
                    }
                  >
                    <option value={0}>Select team</option>

                    {organizationTeams
                      .filter((team) => team.id !== form.homeTeamId)
                      .map((team) => (
                        <option key={team.id} value={team.id}>
                          {team.name}
                        </option>
                      ))}
                  </select>
                </label>

                <label>
                  Scheduled start
                  <input
                    required
                    type="datetime-local"
                    value={form.scheduledStart}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        scheduledStart: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Timezone
                  <select
                    required
                    value={form.timezone}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        timezone: event.target.value,
                      })
                    }
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
                    onChange={(event) =>
                      setForm({
                        ...form,
                        venue: event.target.value,
                      })
                    }
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
                      setForm({
                        ...form,
                        homeScore: Number(event.target.value),
                      })
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
                      setForm({
                        ...form,
                        awayScore: Number(event.target.value),
                      })
                    }
                  />
                </label>

                <label>
                  Notes
                  <textarea
                    value={form.notes}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        notes: event.target.value,
                      })
                    }
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
                <p>{game.organizationName}</p>
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

              {game.notes && <p>{game.notes}</p>}

              {canManage && (
                <div className="cardActions">
                  <button className="secondary" onClick={() => edit(game)}>
                    Edit
                  </button>

                  <button className="danger" onClick={() => void remove(game.id)}>
                    Delete
                  </button>
                </div>
              )}
            </article>
          ))}
        </div>

        {!filteredGames.length && (
          <section className="panel">
            <p>No games match the current filters.</p>
          </section>
        )}
      </AppShell>
    </AuthGate>
  );
}
