"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";

type Organization = { id: number; name: string };
type Season = {
  id: number;
  organizationId: number;
  organizationName: string;
  name: string;
  startDate: string | null;
  endDate: string | null;
  active: boolean;
};
type Form = {
  organizationId: number;
  name: string;
  startDate: string;
  endDate: string;
  active: boolean;
};
const blank: Form = { organizationId: 0, name: "", startDate: "", endDate: "", active: true };

export default function SeasonsPage() {
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [seasons, setSeasons] = useState<Season[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [organizationFilter, setOrganizationFilter] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      const [organizationData, seasonData] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ seasons: Season[] }>("/seasons"),
      ]);
      setOrganizations(organizationData.organizations);
      setSeasons(seasonData.seasons);
      setForm((current) =>
        current.organizationId
          ? current
          : { ...current, organizationId: organizationData.organizations[0]?.id ?? 0 },
      );
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load seasons");
    }
  }, []);

  useEffect(() => {
    load();
    const socket = io(API);
    ["season:created", "season:updated", "season:deleted"].forEach((event) =>
      socket.on(event, load),
    );
    return () => {
      socket.disconnect();
    };
  }, [load]);

  const filtered = useMemo(
    () =>
      seasons.filter(
        (season) =>
          (!organizationFilter || season.organizationId === Number(organizationFilter)) &&
          `${season.name} ${season.organizationName}`.toLowerCase().includes(search.toLowerCase()),
      ),
    [seasons, organizationFilter, search],
  );

  function reset() {
    setEditing(null);
    setError("");
    setForm({ ...blank, organizationId: organizations[0]?.id ?? 0 });
  }

  function edit(season: Season) {
    setEditing(season.id);
    setForm({
      organizationId: season.organizationId,
      name: season.name,
      startDate: season.startDate ?? "",
      endDate: season.endDate ?? "",
      active: season.active,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }

  async function save(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError("");
    try {
      await api(editing ? `/seasons/${editing}` : "/seasons", {
        method: editing ? "PUT" : "POST",
        body: JSON.stringify({
          ...form,
          startDate: form.startDate || null,
          endDate: form.endDate || null,
        }),
      });
      reset();
      await load();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Could not save season");
    } finally {
      setBusy(false);
    }
  }

  async function remove(id: number) {
    if (!confirm("Delete this season?")) return;
    try {
      await api(`/seasons/${id}`, { method: "DELETE" });
      await load();
    } catch (deleteError) {
      setError(deleteError instanceof Error ? deleteError.message : "Could not delete season");
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Seasons</h1>
            <p className="muted">
              Create season records that rosters, schedules, and statistics can reference.
            </p>
          </div>
          <div className="filters">
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
            <input
              className="search"
              placeholder="Search seasons"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
        </div>
        <section className="panel">
          <h2>{editing ? "Edit season" : "Add season"}</h2>
          {organizations.length ? (
            <form className="formGrid" onSubmit={save}>
              <label>
                Organization
                <select
                  required
                  value={form.organizationId}
                  onChange={(event) =>
                    setForm({ ...form, organizationId: Number(event.target.value) })
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
                Season name
                <input
                  required
                  placeholder="2026–27"
                  value={form.name}
                  onChange={(event) => setForm({ ...form, name: event.target.value })}
                />
              </label>
              <label>
                Start date
                <input
                  type="date"
                  value={form.startDate}
                  onChange={(event) => setForm({ ...form, startDate: event.target.value })}
                />
              </label>
              <label>
                End date
                <input
                  type="date"
                  value={form.endDate}
                  onChange={(event) => setForm({ ...form, endDate: event.target.value })}
                />
              </label>
              <label className="check">
                <input
                  type="checkbox"
                  checked={form.active}
                  onChange={(event) => setForm({ ...form, active: event.target.checked })}
                />{" "}
                Active
              </label>
              <div className="formActions">
                <button disabled={busy}>
                  {busy ? "Saving…" : editing ? "Save changes" : "Create season"}
                </button>
                {editing && (
                  <button type="button" className="secondary" onClick={reset}>
                    Cancel
                  </button>
                )}
              </div>
            </form>
          ) : (
            <p>Create an organization first.</p>
          )}
          {error && <p className="error">{error}</p>}
        </section>
        <div className="entityGrid">
          {filtered.map((season) => (
            <article className="entityCard" key={season.id}>
              <div className="entityTop">
                <div className="logo fallback">{season.name.slice(0, 2).toUpperCase()}</div>
                <div>
                  <h3>{season.name}</h3>
                  <p>{season.organizationName}</p>
                </div>
              </div>
              <p>
                {season.startDate || "No start date"} · {season.endDate || "No end date"}
              </p>
              <div className="entityStats">
                <span className={season.active ? "badge" : "badge off"}>
                  {season.active ? "Active" : "Inactive"}
                </span>
              </div>
              <div className="cardActions">
                <button className="secondary" onClick={() => edit(season)}>
                  Edit
                </button>
                <button className="danger" onClick={() => remove(season.id)}>
                  Delete
                </button>
              </div>
            </article>
          ))}
        </div>
      </AppShell>
    </AuthGate>
  );
}
