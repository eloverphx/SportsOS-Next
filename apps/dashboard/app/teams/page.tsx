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

type Org = {
  id: number;
  name: string;
};

type Team = {
  id: number;
  organizationId: number;
  organizationName: string;
  name: string;
  nickname: string | null;
  sport: string;
  division: string | null;
  season: string | null;
  homeArena: string | null;
  primaryColor: string;
  secondaryColor: string;
  logoAssetId: number | null;
  logoUrl: string | null;
  active: boolean;
};

type Form = {
  organizationId: number;
  name: string;
  nickname: string;
  sport: string;
  division: string;
  season: string;
  homeArena: string;
  primaryColor: string;
  secondaryColor: string;
  logoAssetId: number | null;
  active: boolean;
};

const blank: Form = {
  organizationId: 0,
  name: "",
  nickname: "",
  sport: "Hockey",
  division: "",
  season: "2026-27",
  homeArena: "",
  primaryColor: "#ef4444",
  secondaryColor: "#0f172a",
  logoAssetId: null,
  active: true,
};

export default function TeamsPage() {
  const [currentUser, setCurrentUser] = useState<AuthenticatedUser | null>(null);
  const [orgs, setOrgs] = useState<Org[]>([]);
  const [items, setItems] = useState<Team[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [search, setSearch] = useState("");
  const [orgFilter, setOrgFilter] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [file, setFile] = useState<File | null>(null);

  const canCreate = userHasPermission(currentUser, PERMISSIONS.TEAM_CREATE);

  const canUpdate = userHasPermission(currentUser, PERMISSIONS.TEAM_UPDATE);

  const canDelete = userHasPermission(currentUser, PERMISSIONS.TEAM_DELETE);

  const canUseForm = editing !== null ? canUpdate : canCreate;
  const isSystemAdmin = currentUser?.role === "system_admin";

  const load = useCallback(async () => {
    try {
      const [organizationsResponse, teamsResponse] = await Promise.all([
        api<{ organizations: Org[] }>("/organizations"),
        api<{ teams: Team[] }>("/teams"),
      ]);

      setOrgs(organizationsResponse.organizations);
      setItems(teamsResponse.teams);

      setForm((currentForm) =>
        currentForm.organizationId
          ? currentForm
          : {
              ...currentForm,
              organizationId: organizationsResponse.organizations[0]?.id ?? 0,
            },
      );
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Load failed");
    }
  }, []);

  useEffect(() => {
    setCurrentUser(getStoredUser());
  }, []);

  useEffect(() => {
    void load();

    const socket = io(API);

    ["team:created", "team:updated", "team:deleted", "logo:uploaded"].forEach((eventName) =>
      socket.on(eventName, load),
    );

    return () => {
      socket.disconnect();
    };
  }, [load]);

  const filtered = useMemo(
    () =>
      items.filter(
        (team) =>
          (!orgFilter || team.organizationId === Number(orgFilter)) &&
          `${team.name} ${team.nickname ?? ""} ${team.division ?? ""}`
            .toLowerCase()
            .includes(search.toLowerCase()),
      ),
    [items, orgFilter, search],
  );

  function edit(team: Team): void {
    if (!canUpdate) {
      return;
    }

    setEditing(team.id);
    setForm({
      organizationId: team.organizationId,
      name: team.name,
      nickname: team.nickname ?? "",
      sport: team.sport,
      division: team.division ?? "",
      season: team.season ?? "",
      homeArena: team.homeArena ?? "",
      primaryColor: team.primaryColor,
      secondaryColor: team.secondaryColor,
      logoAssetId: team.logoAssetId,
      active: team.active,
    });

    window.scrollTo({
      top: 0,
      behavior: "smooth",
    });
  }

  function reset(): void {
    setEditing(null);
    setFile(null);
    setError("");
    setForm({
      ...blank,
      organizationId: orgs[0]?.id ?? 0,
    });
  }

  async function save(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();

    const allowed = editing !== null ? canUpdate : canCreate;

    if (!allowed) {
      setError(
        editing !== null
          ? "You do not have permission to update teams."
          : "You do not have permission to create teams.",
      );

      return;
    }

    setBusy(true);
    setError("");

    try {
      let logoAssetId = form.logoAssetId;

      if (file) {
        logoAssetId = (await uploadLogo(file, form.organizationId)).id;
      }

      await api(editing ? `/teams/${editing}` : "/teams", {
        method: editing ? "PUT" : "POST",
        body: JSON.stringify({
          ...form,
          nickname: form.nickname || null,
          division: form.division || null,
          season: form.season || null,
          homeArena: form.homeArena || null,
          logoAssetId,
        }),
      });

      reset();
      await load();
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number): Promise<void> {
    if (!canDelete) {
      setError("You do not have permission to delete teams.");

      return;
    }

    if (!window.confirm("Delete this team?")) {
      return;
    }

    try {
      await api(`/teams/${id}`, {
        method: "DELETE",
      });

      await load();
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Delete failed");
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Teams</h1>
            <p className="muted">
              Create and organize teams for future games, rosters, and scoreboards.
            </p>
          </div>

          <div className="filters">
            {isSystemAdmin && orgs.length > 1 && (
              <select value={orgFilter} onChange={(event) => setOrgFilter(event.target.value)}>
                <option value="">All organizations</option>

                {orgs.map((organization) => (
                  <option key={organization.id} value={organization.id}>
                    {organization.name}
                  </option>
                ))}
              </select>
            )}

            <input
              className="search"
              placeholder="Search teams"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
        </div>

        {!canCreate && !canUpdate && !canDelete && (
          <section className="panel">
            <h2>Team directory</h2>
            <p className="muted">Your account has read-only access to team information.</p>
          </section>
        )}

        {canUseForm && (
          <section className="panel">
            <h2>{editing ? "Edit team" : "Add team"}</h2>

            {!orgs.length ? (
              <p>Create an organization first.</p>
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
                      })
                    }
                  >
                    {orgs.map((organization) => (
                      <option key={organization.id} value={organization.id}>
                        {organization.name}
                      </option>
                    ))}
                  </select>
                </label>

                <label>
                  Team name
                  <input
                    required
                    value={form.name}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        name: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Nickname
                  <input
                    value={form.nickname}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        nickname: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Sport
                  <input
                    value={form.sport}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        sport: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Division
                  <input
                    value={form.division}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        division: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Season
                  <input
                    value={form.season}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        season: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Home arena
                  <input
                    value={form.homeArena}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        homeArena: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Logo
                  <input
                    type="file"
                    accept="image/png,image/jpeg,image/webp,image/svg+xml"
                    onChange={(event) => setFile(event.target.files?.[0] ?? null)}
                  />
                </label>

                <label>
                  Primary color
                  <input
                    type="color"
                    value={form.primaryColor}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        primaryColor: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Secondary color
                  <input
                    type="color"
                    value={form.secondaryColor}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        secondaryColor: event.target.value,
                      })
                    }
                  />
                </label>

                <label className="check">
                  <input
                    type="checkbox"
                    checked={form.active}
                    onChange={(event) =>
                      setForm({
                        ...form,
                        active: event.target.checked,
                      })
                    }
                  />{" "}
                  Active
                </label>

                <div className="formActions">
                  <button disabled={busy}>
                    {busy ? "Saving…" : editing ? "Save changes" : "Create team"}
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
          {filtered.map((team) => (
            <article className="entityCard" key={team.id}>
              <div className="entityTop">
                {team.logoUrl ? (
                  <img className="logo" src={team.logoUrl} alt="" />
                ) : (
                  <div
                    className="logo fallback"
                    style={{
                      background: team.primaryColor,
                    }}
                  >
                    {(team.nickname || team.name).slice(0, 2).toUpperCase()}
                  </div>
                )}

                <div>
                  <h3>{team.name}</h3>
                  <p>{team.organizationName}</p>
                </div>
              </div>

              <p>
                {[team.division, team.season, team.homeArena].filter(Boolean).join(" · ") ||
                  "No team details yet"}
              </p>

              <div className="swatches">
                <span
                  style={{
                    background: team.primaryColor,
                  }}
                />
                <span
                  style={{
                    background: team.secondaryColor,
                  }}
                />
              </div>

              <div className="entityStats">
                <b>{team.sport}</b>
                <span className={team.active ? "badge" : "badge off"}>
                  {team.active ? "Active" : "Inactive"}
                </span>
              </div>

              {(canUpdate || canDelete) && (
                <div className="cardActions">
                  {canUpdate && (
                    <button className="secondary" onClick={() => edit(team)}>
                      Edit
                    </button>
                  )}

                  {canDelete && (
                    <button className="danger" onClick={() => void remove(team.id)}>
                      Delete
                    </button>
                  )}
                </div>
              )}
            </article>
          ))}
        </div>
      </AppShell>
    </AuthGate>
  );
}
