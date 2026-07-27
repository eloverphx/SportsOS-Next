"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api, uploadLogo } from "../../lib/api";

type Organization = {
  id: number;
  name: string;
  shortName: string | null;
  defaultSport: string;
  timezone: string;
  primaryColor: string;
  secondaryColor: string;
  website: string | null;
  logoAssetId: number | null;
  logoUrl: string | null;
  active: boolean;
  teamCount: number;
};
type Form = Omit<Organization, "id" | "logoUrl" | "teamCount">;
const blank: Form = {
  name: "",
  shortName: "",
  defaultSport: "Hockey",
  timezone: "America/Chicago",
  primaryColor: "#ef4444",
  secondaryColor: "#0f172a",
  website: "",
  logoAssetId: null,
  active: true,
};
export default function OrganizationsPage() {
  const [items, setItems] = useState<Organization[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<number | null>(null);
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const load = useCallback(
    () =>
      api<{ organizations: Organization[] }>("/organizations")
        .then((d) => setItems(d.organizations))
        .catch((e) => setError(e.message)),
    [],
  );
  useEffect(() => {
    load();
    const socket = io(API);
    [
      "organization:created",
      "organization:updated",
      "organization:deleted",
      "logo:uploaded",
    ].forEach((e) => socket.on(e, load));
    return () => {
      socket.disconnect();
    };
  }, [load]);
  const filtered = useMemo(
    () =>
      items.filter((x) =>
        `${x.name} ${x.shortName ?? ""}`.toLowerCase().includes(search.toLowerCase()),
      ),
    [items, search],
  );
  function edit(x: Organization) {
    setEditing(x.id);
    setForm({
      name: x.name,
      shortName: x.shortName,
      defaultSport: x.defaultSport,
      timezone: x.timezone,
      primaryColor: x.primaryColor,
      secondaryColor: x.secondaryColor,
      website: x.website,
      logoAssetId: x.logoAssetId,
      active: x.active,
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  function reset() {
    setEditing(null);
    setForm(blank);
    setFile(null);
    setError("");
  }
  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      let logoAssetId = form.logoAssetId;
      if (file) logoAssetId = (await uploadLogo(file, editing)).id;
      const payload = {
        ...form,
        shortName: form.shortName || null,
        website: form.website || null,
        logoAssetId,
      };
      await api(editing ? `/organizations/${editing}` : "/organizations", {
        method: editing ? "PUT" : "POST",
        body: JSON.stringify(payload),
      });
      reset();
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }
  async function remove(id: number) {
    if (!confirm("Delete this organization? It must have no teams.")) return;
    try {
      await api(`/organizations/${id}`, { method: "DELETE" });
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
            <h1>Organizations</h1>
            <p className="muted">Manage clubs, schools, leagues, branding, and defaults.</p>
          </div>
          <input
            className="search"
            placeholder="Search organizations"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
        <section className="panel">
          <h2>{editing ? "Edit organization" : "Add organization"}</h2>
          <form className="formGrid" onSubmit={save}>
            <label>
              Name
              <input
                required
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </label>
            <label>
              Short name
              <input
                value={form.shortName ?? ""}
                onChange={(e) => setForm({ ...form, shortName: e.target.value })}
              />
            </label>
            <label>
              Default sport
              <input
                value={form.defaultSport}
                onChange={(e) => setForm({ ...form, defaultSport: e.target.value })}
              />
            </label>
            <label>
              Timezone
              <input
                value={form.timezone}
                onChange={(e) => setForm({ ...form, timezone: e.target.value })}
              />
            </label>
            <label>
              Primary color
              <input
                type="color"
                value={form.primaryColor}
                onChange={(e) => setForm({ ...form, primaryColor: e.target.value })}
              />
            </label>
            <label>
              Secondary color
              <input
                type="color"
                value={form.secondaryColor}
                onChange={(e) => setForm({ ...form, secondaryColor: e.target.value })}
              />
            </label>
            <label>
              Website
              <input
                type="url"
                value={form.website ?? ""}
                onChange={(e) => setForm({ ...form, website: e.target.value })}
              />
            </label>
            <label>
              Logo
              <input
                type="file"
                accept="image/png,image/jpeg,image/webp,image/svg+xml"
                onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              />
            </label>
            <label className="check">
              <input
                type="checkbox"
                checked={form.active}
                onChange={(e) => setForm({ ...form, active: e.target.checked })}
              />{" "}
              Active
            </label>
            <div className="formActions">
              <button disabled={busy}>
                {busy ? "Saving…" : editing ? "Save changes" : "Create organization"}
              </button>
              {editing && (
                <button type="button" className="secondary" onClick={reset}>
                  Cancel
                </button>
              )}
            </div>
          </form>
          {error && <p className="error">{error}</p>}
        </section>
        <div className="entityGrid">
          {filtered.map((x) => (
            <article className="entityCard" key={x.id}>
              <div className="entityTop">
                {x.logoUrl ? (
                  <img className="logo" src={x.logoUrl} alt="" />
                ) : (
                  <div className="logo fallback" style={{ background: x.primaryColor }}>
                    {(x.shortName || x.name).slice(0, 2).toUpperCase()}
                  </div>
                )}
                <div>
                  <h3>{x.name}</h3>
                  <p>
                    {x.defaultSport} · {x.timezone}
                  </p>
                </div>
              </div>
              <div className="swatches">
                <span style={{ background: x.primaryColor }} />
                <span style={{ background: x.secondaryColor }} />
              </div>
              <div className="entityStats">
                <b>{x.teamCount}</b>
                <span>Teams</span>
                <span className={x.active ? "badge" : "badge off"}>
                  {x.active ? "Active" : "Inactive"}
                </span>
              </div>
              <div className="cardActions">
                <button className="secondary" onClick={() => edit(x)}>
                  Edit
                </button>
                <button className="danger" onClick={() => remove(x.id)}>
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
