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

type Organization = {
  id: number;
  name: string;
};

type Team = {
  id: number;
  organizationId: number;
  name: string;
};

type Season = {
  id: number;
  organizationId: number;
  name: string;
  active: boolean;
};

type Position = "Goalie" | "Defense" | "Left Wing" | "Center" | "Right Wing";

type Role = "PLAYER" | "CAPTAIN" | "ALTERNATE";

type Player = {
  id: number;
  organizationId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
  position: Position;
  photoUrl: string | null;
  status: string;
};

type RosterEntry = {
  id: number;
  seasonId: number;
  seasonName: string;
  teamId: number;
  teamName: string;
  playerId: number;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  playerStatus: string;
  photoUrl: string | null;
  jerseyNumber: number | null;
  position: Position;
  role: Role;
  active: boolean;
};

type EditForm = {
  jerseyNumber: string;
  position: Position;
  role: Role;
  active: boolean;
};

const positions: Position[] = ["Goalie", "Defense", "Left Wing", "Center", "Right Wing"];

const roles: Array<{
  value: Role;
  label: string;
}> = [
  { value: "PLAYER", label: "Player" },
  { value: "CAPTAIN", label: "Captain" },
  { value: "ALTERNATE", label: "Alternate" },
];

export default function RostersPage() {
  const [currentUser, setCurrentUser] = useState<AuthenticatedUser | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [seasons, setSeasons] = useState<Season[]>([]);
  const [organizationId, setOrganizationId] = useState<number>(0);
  const [teamId, setTeamId] = useState<number>(0);
  const [seasonId, setSeasonId] = useState<number>(0);
  const [roster, setRoster] = useState<RosterEntry[]>([]);
  const [available, setAvailable] = useState<Player[]>([]);
  const [search, setSearch] = useState("");
  const [editing, setEditing] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<EditForm>({
    jerseyNumber: "",
    position: "Center",
    role: "PLAYER",
    active: true,
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const canManage = userHasPermission(currentUser, PERMISSIONS.TEAM_ROSTER_MANAGE);

  const isSystemAdmin = currentUser?.role === "system_admin";

  const organizationTeams = useMemo(
    () => teams.filter((team) => team.organizationId === organizationId),
    [teams, organizationId],
  );

  const organizationSeasons = useMemo(
    () => seasons.filter((season) => season.organizationId === organizationId),
    [seasons, organizationId],
  );

  const filteredAvailable = useMemo(() => {
    const needle = search.trim().toLowerCase();

    if (!needle) {
      return available;
    }

    return available.filter((player) =>
      `${player.firstName} ${player.lastName} ${player.preferredName ?? ""} ${player.jerseyNumber ?? ""}`
        .toLowerCase()
        .includes(needle),
    );
  }, [available, search]);

  const loadFoundation = useCallback(async () => {
    try {
      const [organizationResponse, teamResponse, seasonResponse] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ teams: Team[] }>("/teams"),
        api<{ seasons: Season[] }>("/seasons"),
      ]);

      setOrganizations(organizationResponse.organizations);
      setTeams(teamResponse.teams);
      setSeasons(seasonResponse.seasons);

      setOrganizationId((current) => current || organizationResponse.organizations[0]?.id || 0);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load roster setup data");
    }
  }, []);

  const loadRoster = useCallback(async () => {
    if (!organizationId || !teamId || !seasonId) {
      setRoster([]);
      setAvailable([]);
      return;
    }

    try {
      setError("");

      const rosterResponse = await api<{
        roster: RosterEntry[];
      }>(`/rosters?seasonId=${seasonId}&teamId=${teamId}`);

      setRoster(rosterResponse.roster);

      if (canManage) {
        const availableResponse = await api<{
          players: Player[];
        }>(
          `/rosters/available?organizationId=${organizationId}&seasonId=${seasonId}&teamId=${teamId}`,
        );

        setAvailable(availableResponse.players);
      } else {
        setAvailable([]);
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load roster");
    }
  }, [organizationId, teamId, seasonId, canManage]);

  useEffect(() => {
    setCurrentUser(getStoredUser());
  }, []);

  useEffect(() => {
    void loadFoundation();
  }, [loadFoundation]);

  useEffect(() => {
    const firstTeam = organizationTeams[0]?.id ?? 0;
    const firstActiveSeason =
      organizationSeasons.find((season) => season.active)?.id ?? organizationSeasons[0]?.id ?? 0;

    if (!organizationTeams.some((team) => team.id === teamId)) {
      setTeamId(firstTeam);
    }

    if (!organizationSeasons.some((season) => season.id === seasonId)) {
      setSeasonId(firstActiveSeason);
    }
  }, [organizationId, organizationTeams, organizationSeasons, teamId, seasonId]);

  useEffect(() => {
    void loadRoster();
  }, [loadRoster]);

  useEffect(() => {
    const socket = io(API);

    const refresh = (): void => {
      void loadRoster();
    };

    socket.on("roster:created", refresh);
    socket.on("roster:updated", refresh);
    socket.on("roster:deleted", refresh);
    socket.on("player:updated", refresh);

    return () => {
      socket.disconnect();
    };
  }, [loadRoster]);

  async function addPlayer(player: Player): Promise<void> {
    if (!canManage) {
      setError("You do not have permission to manage rosters.");
      return;
    }

    if (!teamId || !seasonId) {
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api("/rosters", {
        method: "POST",
        body: JSON.stringify({
          seasonId,
          teamId,
          playerId: player.id,
          jerseyNumber: player.jerseyNumber,
          position: player.position,
          role: "PLAYER",
          active: true,
        }),
      });

      await loadRoster();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not add player");
    } finally {
      setBusy(false);
    }
  }

  function beginEdit(entry: RosterEntry): void {
    if (!canManage) {
      return;
    }

    setEditing(entry.id);
    setEditForm({
      jerseyNumber: entry.jerseyNumber?.toString() ?? "",
      position: entry.position,
      role: entry.role,
      active: entry.active,
    });
  }

  async function saveEdit(entryId: number): Promise<void> {
    if (!canManage) {
      setError("You do not have permission to manage rosters.");
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api(`/rosters/${entryId}`, {
        method: "PUT",
        body: JSON.stringify({
          jerseyNumber: editForm.jerseyNumber === "" ? null : Number(editForm.jerseyNumber),
          position: editForm.position,
          role: editForm.role,
          active: editForm.active,
        }),
      });

      setEditing(null);
      await loadRoster();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not update roster entry");
    } finally {
      setBusy(false);
    }
  }

  async function removeEntry(entry: RosterEntry): Promise<void> {
    if (!canManage) {
      setError("You do not have permission to manage rosters.");
      return;
    }

    if (
      !window.confirm(
        `Remove ${entry.preferredName || entry.firstName} ${entry.lastName} from this roster?`,
      )
    ) {
      return;
    }

    setBusy(true);
    setError("");

    try {
      await api(`/rosters/${entry.id}`, {
        method: "DELETE",
      });

      await loadRoster();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not remove player");
    } finally {
      setBusy(false);
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Roster Workspace</h1>
            <p className="muted">
              Build season-aware team rosters, assign jersey numbers, and designate captains.
            </p>
          </div>

          <div className="filters">
            {isSystemAdmin ? (
              <select
                value={organizationId || ""}
                onChange={(event) => setOrganizationId(Number(event.target.value))}
              >
                <option value="">Select organization</option>

                {organizations.map((organization) => (
                  <option key={organization.id} value={organization.id}>
                    {organization.name}
                  </option>
                ))}
              </select>
            ) : (
              <select value={organizationId || ""} disabled>
                {organizations.map((organization) => (
                  <option key={organization.id} value={organization.id}>
                    {organization.name}
                  </option>
                ))}
              </select>
            )}

            <select
              value={seasonId || ""}
              onChange={(event) => setSeasonId(Number(event.target.value))}
              disabled={!organizationId}
            >
              <option value="">Select season</option>

              {organizationSeasons.map((season) => (
                <option key={season.id} value={season.id}>
                  {season.name}
                  {season.active ? " · Active" : ""}
                </option>
              ))}
            </select>

            <select
              value={teamId || ""}
              onChange={(event) => setTeamId(Number(event.target.value))}
              disabled={!organizationId}
            >
              <option value="">Select team</option>

              {organizationTeams.map((team) => (
                <option key={team.id} value={team.id}>
                  {team.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        {!canManage && (
          <section className="panel">
            <h2>Roster directory</h2>
            <p className="muted">Your account has read-only access to team rosters.</p>
          </section>
        )}

        {error && <p className="error">{error}</p>}

        {!organizationId || !seasonId || !teamId ? (
          <section className="panel">
            <p>Select an organization, season, and team to view a roster.</p>
          </section>
        ) : (
          <div className="rosterWorkspace">
            {canManage && (
              <section className="panel">
                <div className="sectionHead">
                  <div>
                    <h2>Available Players</h2>
                    <p className="muted">
                      {available.length} player
                      {available.length === 1 ? "" : "s"} available
                    </p>
                  </div>

                  <input
                    className="search"
                    placeholder="Search players"
                    value={search}
                    onChange={(event) => setSearch(event.target.value)}
                  />
                </div>

                <div className="rosterList">
                  {filteredAvailable.map((player) => (
                    <article className="rosterRow" key={player.id}>
                      <div className="entityTop">
                        {player.photoUrl ? (
                          <img className="logo playerPhoto" src={player.photoUrl} alt="" />
                        ) : (
                          <div className="logo fallback playerPhoto">
                            {player.firstName[0]}
                            {player.lastName[0]}
                          </div>
                        )}

                        <div>
                          <h3>
                            {player.preferredName || player.firstName} {player.lastName}
                          </h3>
                          <p>
                            {player.position} · {player.status}
                          </p>
                        </div>
                      </div>

                      <button disabled={busy} onClick={() => void addPlayer(player)}>
                        Add
                      </button>
                    </article>
                  ))}
                </div>

                {!filteredAvailable.length && (
                  <p className="muted">No available players match this search.</p>
                )}
              </section>
            )}

            <section className="panel">
              <div className="sectionHead">
                <div>
                  <h2>Team Roster</h2>
                  <p className="muted">
                    {roster.filter((entry) => entry.active).length} active · {roster.length} total
                  </p>
                </div>
              </div>

              <div className="rosterList">
                {roster.map((entry) => (
                  <article className="rosterRow rosterEntry" key={entry.id}>
                    {editing === entry.id && canManage ? (
                      <div className="rosterEdit">
                        <label>
                          Jersey
                          <input
                            type="number"
                            min="0"
                            max="99"
                            value={editForm.jerseyNumber}
                            onChange={(event) =>
                              setEditForm({
                                ...editForm,
                                jerseyNumber: event.target.value,
                              })
                            }
                          />
                        </label>

                        <label>
                          Position
                          <select
                            value={editForm.position}
                            onChange={(event) =>
                              setEditForm({
                                ...editForm,
                                position: event.target.value as Position,
                              })
                            }
                          >
                            {positions.map((position) => (
                              <option key={position}>{position}</option>
                            ))}
                          </select>
                        </label>

                        <label>
                          Role
                          <select
                            value={editForm.role}
                            onChange={(event) =>
                              setEditForm({
                                ...editForm,
                                role: event.target.value as Role,
                              })
                            }
                          >
                            {roles.map((role) => (
                              <option key={role.value} value={role.value}>
                                {role.label}
                              </option>
                            ))}
                          </select>
                        </label>

                        <label className="checkLabel">
                          <input
                            type="checkbox"
                            checked={editForm.active}
                            onChange={(event) =>
                              setEditForm({
                                ...editForm,
                                active: event.target.checked,
                              })
                            }
                          />{" "}
                          Active
                        </label>

                        <div className="cardActions">
                          <button disabled={busy} onClick={() => void saveEdit(entry.id)}>
                            Save
                          </button>

                          <button className="secondary" onClick={() => setEditing(null)}>
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <>
                        <div className="entityTop">
                          {entry.photoUrl ? (
                            <img className="logo playerPhoto" src={entry.photoUrl} alt="" />
                          ) : (
                            <div className="logo fallback playerPhoto">
                              {entry.firstName[0]}
                              {entry.lastName[0]}
                            </div>
                          )}

                          <div>
                            <h3>
                              {entry.preferredName || entry.firstName} {entry.lastName}
                            </h3>
                            <p>
                              {entry.position} ·{" "}
                              {entry.role === "ALTERNATE"
                                ? "Alternate Captain"
                                : entry.role === "CAPTAIN"
                                  ? "Captain"
                                  : "Player"}
                            </p>
                          </div>
                        </div>

                        <div className="rosterNumber">
                          {entry.jerseyNumber === null ? "—" : `#${entry.jerseyNumber}`}
                        </div>

                        <span className={entry.active ? "badge" : "badge off"}>
                          {entry.active ? "Active" : "Inactive"}
                        </span>

                        {canManage && (
                          <div className="cardActions">
                            <button className="secondary" onClick={() => beginEdit(entry)}>
                              Edit
                            </button>

                            <button
                              className="danger"
                              disabled={busy}
                              onClick={() => void removeEntry(entry)}
                            >
                              Remove
                            </button>
                          </div>
                        )}
                      </>
                    )}
                  </article>
                ))}
              </div>

              {!roster.length && (
                <p className="muted">
                  This team does not have any players assigned for the selected season.
                </p>
              )}
            </section>
          </div>
        )}
      </AppShell>
    </AuthGate>
  );
}
