"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { io } from "socket.io-client";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
  type AuthenticatedUser,
} from "../../lib/auth";

type Organization = { id: number; name: string };
type GameStatus = "SCHEDULED" | "LIVE" | "FINAL" | "POSTPONED" | "CANCELED";

type Game = {
  id: number;
  organizationId: number;
  organizationName: string;
  seasonName: string;
  homeTeamName: string;
  awayTeamName: string;
  scheduledStart: string;
  venue: string | null;
  status: GameStatus;
  homeScore: number;
  awayScore: number;
  period: number;
  clockRemainingMs: number;
  clockRunning: boolean;
  clockStartedAt: string | null;
};

type Device = {
  id: number;
  organizationId: number;
  organizationName: string;
  gameId: number | null;
  gameLabel: string | null;
  name: string;
  location: string | null;
  deviceKey: string;
  status: "ONLINE" | "OFFLINE";
  lastSeenAt: string | null;
};

type DeviceForm = {
  organizationId: number;
  gameId: number | null;
  name: string;
  location: string;
};

const blankDeviceForm: DeviceForm = {
  organizationId: 0,
  gameId: null,
  name: "",
  location: "",
};

const statuses: readonly GameStatus[] = ["SCHEDULED", "LIVE", "FINAL", "POSTPONED", "CANCELED"];

function remainingMs(game: Game, now: number): number {
  if (!game.clockRunning || !game.clockStartedAt) {
    return Math.max(0, game.clockRemainingMs);
  }
  return Math.max(0, game.clockRemainingMs - (now - new Date(game.clockStartedAt).getTime()));
}

function formatClock(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  return `${Math.floor(totalSeconds / 60)}:${String(totalSeconds % 60).padStart(2, "0")}`;
}

export default function ScoreboardsPage() {
  const [user, setUser] = useState<AuthenticatedUser | null>(null);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [games, setGames] = useState<Game[]>([]);
  const [devices, setDevices] = useState<Device[]>([]);
  const [deviceForm, setDeviceForm] = useState<DeviceForm>(blankDeviceForm);
  const [editingDeviceId, setEditingDeviceId] = useState<number | null>(null);
  const [statusFilter, setStatusFilter] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());

  const canManageDevices = userHasPermission(user, PERMISSIONS.SCOREBOARD_MANAGE);
  const isSystemAdmin = user?.role === "system_admin";

  const organizationGames = useMemo(
    () => games.filter((game) => game.organizationId === deviceForm.organizationId),
    [games, deviceForm.organizationId],
  );

  const load = useCallback(async () => {
    try {
      const [organizationResponse, gameResponse, deviceResponse] = await Promise.all([
        api<{ organizations: Organization[] }>("/organizations"),
        api<{ games: Game[] }>("/games"),
        api<{ devices: Device[] }>("/scoreboard-devices"),
      ]);

      setOrganizations(organizationResponse.organizations);
      setGames(gameResponse.games);
      setDevices(deviceResponse.devices);
      setDeviceForm((current) =>
        current.organizationId
          ? current
          : {
              ...current,
              organizationId: organizationResponse.organizations[0]?.id ?? 0,
            },
      );
      setError("");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load scoreboards");
    }
  }, []);

  useEffect(() => setUser(getStoredUser()), []);

  useEffect(() => {
    void load();
    const socket = io(API);

    [
      "game:created",
      "game:updated",
      "game:deleted",
      "game:scored",
      "scoreboard-device:created",
      "scoreboard-device:updated",
      "scoreboard-device:deleted",
      "scoreboard-device:status",
    ].forEach((eventName) => socket.on(eventName, load));

    return () => {
      socket.disconnect();
    };
  }, [load]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  const filteredGames = useMemo(
    () =>
      games.filter((game) => {
        const text =
          `${game.homeTeamName} ${game.awayTeamName} ${game.organizationName} ${game.venue ?? ""}`.toLowerCase();
        return (
          (!statusFilter || game.status === statusFilter) &&
          text.includes(search.trim().toLowerCase())
        );
      }),
    [games, search, statusFilter],
  );

  function resetDeviceForm(): void {
    setEditingDeviceId(null);
    setDeviceForm({
      ...blankDeviceForm,
      organizationId: organizations[0]?.id ?? 0,
    });
  }

  function editDevice(device: Device): void {
    setEditingDeviceId(device.id);
    setDeviceForm({
      organizationId: device.organizationId,
      gameId: device.gameId,
      name: device.name,
      location: device.location ?? "",
    });
  }

  async function saveDevice(event: React.FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    if (!canManageDevices) return;

    setBusy(true);
    setError("");

    try {
      await api(
        editingDeviceId ? `/scoreboard-devices/${editingDeviceId}` : "/scoreboard-devices",
        {
          method: editingDeviceId ? "PUT" : "POST",
          body: JSON.stringify({
            ...deviceForm,
            location: deviceForm.location || null,
          }),
        },
      );

      resetDeviceForm();
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not save scoreboard device");
    } finally {
      setBusy(false);
    }
  }

  async function removeDevice(id: number): Promise<void> {
    if (!canManageDevices || !window.confirm("Delete this scoreboard device?")) {
      return;
    }

    try {
      await api(`/scoreboard-devices/${id}`, { method: "DELETE" });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not delete scoreboard device");
    }
  }

  async function rotateKey(id: number): Promise<void> {
    if (
      !canManageDevices ||
      !window.confirm("Rotate this device key? The old key will stop working.")
    ) {
      return;
    }

    try {
      await api(`/scoreboard-devices/${id}/rotate-key`, {
        method: "POST",
      });
      await load();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not rotate device key");
    }
  }

  async function copy(value: string, label: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(label);
      window.setTimeout(() => setCopied(null), 1800);
    } catch {
      setError("Could not copy to clipboard.");
    }
  }

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>Scoreboards</h1>
            <p className="muted">Monitor games and manage physical scoreboard devices.</p>
          </div>

          <div className="filters">
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
              placeholder="Search scoreboards"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
            />
          </div>
        </div>

        {error && <p className="error">{error}</p>}

        {canManageDevices && (
          <section className="panel">
            <h2>{editingDeviceId ? "Edit scoreboard device" : "Register scoreboard device"}</h2>

            <form className="formGrid" onSubmit={saveDevice}>
              <label>
                Organization
                <select
                  required
                  disabled={!isSystemAdmin}
                  value={deviceForm.organizationId}
                  onChange={(event) =>
                    setDeviceForm({
                      ...deviceForm,
                      organizationId: Number(event.target.value),
                      gameId: null,
                    })
                  }
                >
                  <option value={0}>Select organization</option>
                  {organizations.map((organization) => (
                    <option key={organization.id} value={organization.id}>
                      {organization.name}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                Device name
                <input
                  required
                  maxLength={160}
                  value={deviceForm.name}
                  onChange={(event) =>
                    setDeviceForm({
                      ...deviceForm,
                      name: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Location
                <input
                  maxLength={160}
                  value={deviceForm.location}
                  onChange={(event) =>
                    setDeviceForm({
                      ...deviceForm,
                      location: event.target.value,
                    })
                  }
                />
              </label>

              <label>
                Assigned game
                <select
                  value={deviceForm.gameId ?? ""}
                  onChange={(event) =>
                    setDeviceForm({
                      ...deviceForm,
                      gameId: event.target.value ? Number(event.target.value) : null,
                    })
                  }
                >
                  <option value="">Unassigned</option>
                  {organizationGames.map((game) => (
                    <option key={game.id} value={game.id}>
                      {game.awayTeamName} at {game.homeTeamName}
                    </option>
                  ))}
                </select>
              </label>

              <div className="formActions">
                <button disabled={busy}>{busy ? "Saving…" : "Save device"}</button>
                {editingDeviceId && (
                  <button type="button" className="secondary" onClick={resetDeviceForm}>
                    Cancel
                  </button>
                )}
              </div>
            </form>
          </section>
        )}

        <section className="panel">
          <div className="sectionHead">
            <div>
              <h2>Registered devices</h2>
              <p className="muted">Devices are online when they heartbeat within 90 seconds.</p>
            </div>
          </div>

          <div className="entityGrid">
            {devices.map((device) => (
              <article className="entityCard" key={device.id}>
                <div className="sectionHead">
                  <div>
                    <h3>{device.name}</h3>
                    <p>{device.organizationName}</p>
                  </div>
                  <span className={device.status === "ONLINE" ? "badge" : "badge off"}>
                    {device.status}
                  </span>
                </div>

                <p>{device.location || "Location not set"}</p>
                <p>{device.gameLabel || "No game assigned"}</p>
                <p>
                  Last seen:{" "}
                  {device.lastSeenAt ? new Date(device.lastSeenAt).toLocaleString() : "Never"}
                </p>

                {canManageDevices && (
                  <>
                    <label className="deviceKeyLabel">
                      Device key
                      <input readOnly value={device.deviceKey} />
                    </label>

                    <div className="cardActions">
                      {device.gameId && (
                        <Link href={`/scoreboards/${device.id}/control`}>Control</Link>
                      )}

                      <button
                        className="secondary"
                        onClick={() => void copy(device.deviceKey, `key-${device.id}`)}
                      >
                        {copied === `key-${device.id}` ? "Copied" : "Copy key"}
                      </button>
                      <button className="secondary" onClick={() => editDevice(device)}>
                        Edit
                      </button>
                      <button className="secondary" onClick={() => void rotateKey(device.id)}>
                        Rotate key
                      </button>
                      <button className="danger" onClick={() => void removeDevice(device.id)}>
                        Delete
                      </button>
                    </div>
                  </>
                )}
              </article>
            ))}
          </div>

          {!devices.length && <p>No scoreboard devices registered.</p>}
        </section>

        <div className="scoreboardWorkspaceGrid">
          {filteredGames.map((game) => (
            <article className="scoreboardWorkspaceCard" key={game.id}>
              <div className="scoreboardWorkspaceHead">
                <div>
                  <span className="eyebrow">{game.organizationName}</span>
                  <h2>
                    {game.awayTeamName} at {game.homeTeamName}
                  </h2>
                </div>
                <span className={game.status === "LIVE" ? "badge" : "badge off"}>
                  {game.status}
                </span>
              </div>

              <div className="scoreboardWorkspacePreview">
                <div>
                  <span>{game.awayTeamName}</span>
                  <b>{game.awayScore}</b>
                </div>
                <div className="scoreboardWorkspaceClock">
                  <span>Period {game.period}</span>
                  <b>{formatClock(remainingMs(game, now))}</b>
                  <small>{game.clockRunning ? "Running" : "Paused"}</small>
                </div>
                <div>
                  <span>{game.homeTeamName}</span>
                  <b>{game.homeScore}</b>
                </div>
              </div>

              <div className="cardActions">
                <Link
                  href={`/games/${game.id}/scoreboard`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  Open scoreboard
                </Link>
                <Link href={`/games/${game.id}/overlay`} target="_blank" rel="noopener noreferrer">
                  Open overlay
                </Link>
                <button
                  className="secondary"
                  onClick={() =>
                    void copy(
                      `${window.location.origin}/games/${game.id}/scoreboard`,
                      `url-${game.id}`,
                    )
                  }
                >
                  {copied === `url-${game.id}` ? "Copied" : "Copy URL"}
                </button>
              </div>
            </article>
          ))}
        </div>
      </AppShell>
    </AuthGate>
  );
}
