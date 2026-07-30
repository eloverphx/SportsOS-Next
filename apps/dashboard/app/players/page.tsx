"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api, uploadLogo } from "../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
} from "../../lib/auth";

type Organization = { id: number; name: string };
type Team = { id: number; organizationId: number; name: string };
type Player = {
  id: number;
  organizationId: number;
  organizationName: string;
  teamId: number | null;
  teamName: string | null;
  firstName: string;
  lastName: string;
  preferredName: string | null;
  jerseyNumber: number | null;
  position: "Goalie" | "Defense" | "Left Wing" | "Center" | "Right Wing";
  shoots: "L" | "R" | null;
  birthDate: string | null;
  heightCm: number | null;
  weightKg: number | null;
  email: string | null;
  phone: string | null;
  photoAssetId: number | null;
  photoUrl: string | null;
  status: "ACTIVE" | "INACTIVE" | "INJURED" | "SUSPENDED";
};
type Form = {
  organizationId: number;
  teamId: number | null;
  firstName: string;
  lastName: string;
  preferredName: string;
  jerseyNumber: string;
  position: Player["position"];
  shoots: "" | "L" | "R";
  birthDate: string;
  heightCm: string;
  weightKg: string;
  email: string;
  phone: string;
  photoAssetId: number | null;
  status: Player["status"];
};
const blank: Form = {
  organizationId: 0,
  teamId: null,
  firstName: "",
  lastName: "",
  preferredName: "",
  jerseyNumber: "",
  position: "Center",
  shoots: "",
  birthDate: "",
  heightCm: "",
  weightKg: "",
  email: "",
  phone: "",
  photoAssetId: null,
  status: "ACTIVE",
};

export default function PlayersPage() {
  const [currentUser, setCurrentUser] = useState<AuthenticatedUser | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [teams, setTeams] = useState<Team[]>([]);
  const [players, setPlayers] = useState<Player[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [search, setSearch] = useState("");
  const [organizationFilter, setOrganizationFilter] = useState("");
  const [teamFilter, setTeamFilter] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [file, setFile] = useState<File | null>(null);

  const canManage = userHasPermission(currentUser, PERMISSIONS.PLAYER_MANAGE);

  const isSystemAdmin = currentUser?.role === "system_admin";
  const load = useCallback(async () => {
    try {
      const [o, t, p] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ teams: Team[] }>("/teams"),
        api<{ players: Player[] }>("/players"),
      ]);
      setOrganizations(o.organizations);
      setTeams(t.teams);
      setPlayers(p.players);
      setForm((f) =>
        f.organizationId ? f : { ...f, organizationId: o.organizations[0]?.id ?? 0 },
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Load failed");
    }
  }, []);
  useEffect(() => {
    setCurrentUser(getStoredUser());
  }, []);

  useEffect(() => {
    void load();
    const socket = io(API);
    ["player:created", "player:updated", "player:deleted", "logo:uploaded", "team:updated"].forEach(
      (event) => socket.on(event, load),
    );
    return () => {
      socket.disconnect();
    };
  }, [load]);
  const availableTeams = useMemo(
    () => teams.filter((t) => t.organizationId === form.organizationId),
    [teams, form.organizationId],
  );
  const filterTeams = useMemo(
    () =>
      teams.filter((t) => !organizationFilter || t.organizationId === Number(organizationFilter)),
    [teams, organizationFilter],
  );
  const filtered = useMemo(
    () =>
      players.filter((player) => {
        const text =
          `${player.firstName} ${player.lastName} ${player.preferredName ?? ""} ${player.jerseyNumber ?? ""}`.toLowerCase();
        return (
          (!organizationFilter || player.organizationId === Number(organizationFilter)) &&
          (!teamFilter || player.teamId === Number(teamFilter)) &&
          (!statusFilter || player.status === statusFilter) &&
          text.includes(search.toLowerCase())
        );
      }),
    [players, organizationFilter, teamFilter, statusFilter, search],
  );
  function reset() {
    setEditing(null);
    setFile(null);
    setError("");
    setForm({ ...blank, organizationId: organizations[0]?.id ?? 0 });
  }
  function edit(player: Player): void {
    if (!canManage) return;

    setEditing(player.id);
    setForm({
      organizationId: player.organizationId,
      teamId: player.teamId,
      firstName: player.firstName,
      lastName: player.lastName,
      preferredName: player.preferredName ?? "",
      jerseyNumber: player.jerseyNumber?.toString() ?? "",
      position: player.position,
      shoots: player.shoots ?? "",
      birthDate: player.birthDate ?? "",
      heightCm: player.heightCm?.toString() ?? "",
      weightKg: player.weightKg?.toString() ?? "",
      email: player.email ?? "",
      phone: player.phone ?? "",
      photoAssetId: player.photoAssetId,
      status: player.status,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  async function save(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    if (!canManage) {
      setError("You do not have permission to manage players.");
      return;
    }

    setBusy(true);
    setError("");
    try {
      let photoAssetId = form.photoAssetId;
      if (file) photoAssetId = (await uploadLogo(file, form.organizationId)).id;
      const body = {
        ...form,
        teamId: form.teamId || null,
        preferredName: form.preferredName || null,
        jerseyNumber: form.jerseyNumber === "" ? null : Number(form.jerseyNumber),
        shoots: form.shoots || null,
        birthDate: form.birthDate || null,
        heightCm: form.heightCm === "" ? null : Number(form.heightCm),
        weightKg: form.weightKg === "" ? null : Number(form.weightKg),
        email: form.email || null,
        phone: form.phone || null,
        photoAssetId,
      };
      await api(editing ? `/players/${editing}` : "/players", {
        method: editing ? "PUT" : "POST",
        body: JSON.stringify(body),
      });
      reset();
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }
  async function remove(id: number): Promise<void> {
    if (!canManage) {
      setError("You do not have permission to manage players.");
      return;
    }

    if (!window.confirm("Delete this player?")) return;
    try {
      await api(`/players/${id}`, { method: "DELETE" });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Delete failed");
    }
  }
  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Players</h1>
            <p className="muted">Create player profiles and prepare them for team rosters.</p>
          </div>
          <div className="filters">
            {isSystemAdmin && organizations.length > 1 && (
              <select
                value={organizationFilter}
                onChange={(event) => {
                  setOrganizationFilter(event.target.value);
                  setTeamFilter("");
                }}
              >
                <option value="">All organizations</option>
                {organizations.map((organization) => (
                  <option key={organization.id} value={organization.id}>
                    {organization.name}
                  </option>
                ))}
              </select>
            )}
            <select value={teamFilter} onChange={(e) => setTeamFilter(e.target.value)}>
              <option value="">All teams</option>
              {filterTeams.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
            <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
              <option value="">All statuses</option>
              <option>ACTIVE</option>
              <option>INACTIVE</option>
              <option>INJURED</option>
              <option>SUSPENDED</option>
            </select>
            <input
              className="search"
              placeholder="Search players"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>
        {!canManage && (
          <section className="panel">
            <h2>Player directory</h2>
            <p className="muted">Your account has read-only access to player information.</p>
          </section>
        )}

        {canManage && (
          <section className="panel">
            <h2>{editing ? "Edit player" : "Add player"}</h2>
            {!organizations.length ? (
              <p>Create an organization first.</p>
            ) : (
              <form className="formGrid" onSubmit={save}>
                <label>
                  Organization
                  <select
                    required
                    disabled={!isSystemAdmin}
                    value={form.organizationId}
                    onChange={(e) =>
                      setForm({ ...form, organizationId: Number(e.target.value), teamId: null })
                    }
                  >
                    {organizations.map((o) => (
                      <option key={o.id} value={o.id}>
                        {o.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  Team
                  <select
                    value={form.teamId ?? ""}
                    onChange={(e) =>
                      setForm({ ...form, teamId: e.target.value ? Number(e.target.value) : null })
                    }
                  >
                    <option value="">Unassigned</option>
                    {availableTeams.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  First name
                  <input
                    required
                    value={form.firstName}
                    onChange={(e) => setForm({ ...form, firstName: e.target.value })}
                  />
                </label>
                <label>
                  Last name
                  <input
                    required
                    value={form.lastName}
                    onChange={(e) => setForm({ ...form, lastName: e.target.value })}
                  />
                </label>
                <label>
                  Preferred name
                  <input
                    value={form.preferredName}
                    onChange={(e) => setForm({ ...form, preferredName: e.target.value })}
                  />
                </label>
                <label>
                  Jersey number
                  <input
                    type="number"
                    min="0"
                    max="99"
                    value={form.jerseyNumber}
                    onChange={(e) => setForm({ ...form, jerseyNumber: e.target.value })}
                  />
                </label>
                <label>
                  Position
                  <select
                    value={form.position}
                    onChange={(e) =>
                      setForm({ ...form, position: e.target.value as Player["position"] })
                    }
                  >
                    {["Goalie", "Defense", "Left Wing", "Center", "Right Wing"].map((x) => (
                      <option key={x}>{x}</option>
                    ))}
                  </select>
                </label>
                <label>
                  Shoots
                  <select
                    value={form.shoots}
                    onChange={(e) => setForm({ ...form, shoots: e.target.value as Form["shoots"] })}
                  >
                    <option value="">Not set</option>
                    <option value="L">Left</option>
                    <option value="R">Right</option>
                  </select>
                </label>
                <label>
                  Birth date
                  <input
                    type="date"
                    value={form.birthDate}
                    onChange={(e) => setForm({ ...form, birthDate: e.target.value })}
                  />
                </label>
                <label>
                  Height (cm)
                  <input
                    type="number"
                    min="50"
                    max="260"
                    value={form.heightCm}
                    onChange={(e) => setForm({ ...form, heightCm: e.target.value })}
                  />
                </label>
                <label>
                  Weight (kg)
                  <input
                    type="number"
                    min="15"
                    max="250"
                    value={form.weightKg}
                    onChange={(e) => setForm({ ...form, weightKg: e.target.value })}
                  />
                </label>
                <label>
                  Email
                  <input
                    type="email"
                    value={form.email}
                    onChange={(e) => setForm({ ...form, email: e.target.value })}
                  />
                </label>
                <label>
                  Phone
                  <input
                    value={form.phone}
                    onChange={(e) => setForm({ ...form, phone: e.target.value })}
                  />
                </label>
                <label>
                  Player photo
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp"
                    onChange={(e) => setFile(e.target.files?.[0] ?? null)}
                  />
                </label>
                <label>
                  Status
                  <select
                    value={form.status}
                    onChange={(e) =>
                      setForm({ ...form, status: e.target.value as Player["status"] })
                    }
                  >
                    <option>ACTIVE</option>
                    <option>INACTIVE</option>
                    <option>INJURED</option>
                    <option>SUSPENDED</option>
                  </select>
                </label>
                <div className="formActions">
                  <button disabled={busy}>
                    {busy ? "Saving…" : editing ? "Save changes" : "Create player"}
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
          {filtered.map((player) => (
            <article className="entityCard" key={player.id}>
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
                    {player.teamName ?? "Unassigned"} · {player.organizationName}
                  </p>
                </div>
              </div>
              <div className="playerNumber">
                {player.jerseyNumber === null ? "—" : `#${player.jerseyNumber}`}
              </div>
              <p>
                {player.position}
                {player.shoots ? ` · Shoots ${player.shoots}` : ""}
              </p>
              <div className="entityStats">
                <b>{player.status}</b>
                <span className={player.status === "ACTIVE" ? "badge" : "badge off"}>
                  {player.status === "ACTIVE" ? "Active" : "Unavailable"}
                </span>
              </div>
              {canManage && (
                <div className="cardActions">
                  <button className="secondary" onClick={() => edit(player)}>
                    Edit
                  </button>
                  <button className="danger" onClick={() => void remove(player.id)}>
                    Delete
                  </button>
                </div>
              )}
            </article>
          ))}
        </div>
        {!filtered.length && (
          <section className="panel">
            <p>No players match the current filters.</p>
          </section>
        )}
      </AppShell>
    </AuthGate>
  );
}
