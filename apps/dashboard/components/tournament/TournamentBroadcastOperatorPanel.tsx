"use client";

import { useMemo, useState, useEffect } from "react";
import {
  buildBroadcastSessionSummary,
  type BroadcastOverlayState,
  type BroadcastTransportState,
} from "../../lib/tournament-broadcast-session";
import {
  BROADCAST_THEME_STORAGE_KEY,
  normalizeBroadcastOverlayThemeSettings,
  type BroadcastOverlayThemeSettings,
} from "../../lib/broadcast-overlay-theme-settings";
import {
  BROADCAST_THEME_CHANGED_EVENT,
} from "../../lib/broadcast-overlay-theme-sync";

export function TournamentBroadcastOperatorPanel() {
  const [gameId, setGameId] = useState("");
  const [operatorAssigned, setOperatorAssigned] =
    useState(false);
  const [gameAuthorized, setGameAuthorized] =
    useState(false);
  const [gameLive, setGameLive] = useState(false);
  const [streamKeyConfigured, setStreamKeyConfigured] =
    useState(false);
  const [transportState, setTransportState] =
    useState<BroadcastTransportState>("OFFLINE");
  const [overlayState, setOverlayState] =
    useState<BroadcastOverlayState>("DISABLED");
  const [themeSettings, setThemeSettings] =
    useState<BroadcastOverlayThemeSettings>(() =>
      normalizeBroadcastOverlayThemeSettings(),
    );

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(
        BROADCAST_THEME_STORAGE_KEY,
      );

      if (raw) {
        const parsed = JSON.parse(
          raw,
        ) as Partial<BroadcastOverlayThemeSettings>;

        setThemeSettings(
          normalizeBroadcastOverlayThemeSettings(parsed),
        );
      }
    } catch {
      // Ignore malformed or unavailable local storage.
    }
  }, []);

  useEffect(() => {
    try {
      window.localStorage.setItem(
        BROADCAST_THEME_STORAGE_KEY,
        JSON.stringify(themeSettings),
      );
      window.dispatchEvent(
        new Event(BROADCAST_THEME_CHANGED_EVENT),
      );
    } catch {
      // Operator controls remain usable without persistence.
    }
  }, [themeSettings]);

  const summary = useMemo(
    () =>
      buildBroadcastSessionSummary({
        gameId: gameId.trim() || "unselected-game",
        operatorAssigned,
        gameAuthorized,
        gameLive,
        transportState,
        overlayState,
        streamKeyConfigured,
      }),
    [
      gameAuthorized,
      gameId,
      gameLive,
      operatorAssigned,
      overlayState,
      streamKeyConfigured,
      transportState,
    ],
  );

  return (
    <section
      data-testid="broadcast-operator-panel"
      className="space-y-5"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Broadcast session
            </div>
            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.status}
            </div>
          </div>

          <div className="text-right text-xs text-slate-500">
            {summary.ready ? "Ready" : "Not ready"}
          </div>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Game ID
            </span>
            <input
              value={gameId}
              onChange={(event) =>
                setGameId(event.target.value)
              }
              placeholder="Enter game ID"
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Transport
            </span>
            <select
              value={transportState}
              onChange={(event) =>
                setTransportState(
                  event.target.value as BroadcastTransportState,
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="OFFLINE">OFFLINE</option>
              <option value="CONNECTING">CONNECTING</option>
              <option value="READY">READY</option>
              <option value="LIVE">LIVE</option>
              <option value="ERROR">ERROR</option>
            </select>
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Overlay
            </span>
            <select
              value={overlayState}
              onChange={(event) =>
                setOverlayState(
                  event.target.value as BroadcastOverlayState,
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="DISABLED">DISABLED</option>
              <option value="READY">READY</option>
              <option value="ACTIVE">ACTIVE</option>
            </select>
          </label>
        </div>

        <div className="mt-4 grid gap-3 md:grid-cols-2">
          {[
            [
              "Broadcast operator assigned",
              operatorAssigned,
              setOperatorAssigned,
            ],
            [
              "Game start authorized",
              gameAuthorized,
              setGameAuthorized,
            ],
            [
              "Game currently live",
              gameLive,
              setGameLive,
            ],
            [
              "Stream destination configured",
              streamKeyConfigured,
              setStreamKeyConfigured,
            ],
          ].map(([label, checked, setter]) => (
            <label
              key={String(label)}
              className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2 text-sm text-slate-300"
            >
              <input
                type="checkbox"
                checked={Boolean(checked)}
                onChange={(event) =>
                  (
                    setter as React.Dispatch<
                      React.SetStateAction<boolean>
                    >
                  )(event.target.checked)
                }
              />
              {String(label)}
            </label>
          ))}
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Blockers
          </div>

          <div className="mt-3 space-y-2">
            {summary.blockers.length === 0 ? (
              <div className="text-sm text-emerald-300">
                No broadcast blockers.
              </div>
            ) : (
              summary.blockers.map((blocker) => (
                <div
                  key={blocker}
                  className="rounded-lg border border-red-900/50 bg-red-950/20 px-3 py-2 text-xs text-red-300"
                >
                  {blocker}
                </div>
              ))
            )}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Warnings
          </div>

          <div className="mt-3 space-y-2">
            {summary.warnings.length === 0 ? (
              <div className="text-sm text-slate-400">
                No broadcast warnings.
              </div>
            ) : (
              summary.warnings.map((warning) => (
                <div
                  key={warning}
                  className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
                >
                  {warning}
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <section
        data-testid="broadcast-theme-controls"
        className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
      >
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            Overlay theme
          </div>
          <h2 className="mt-1 text-lg font-bold text-slate-100">
            Branding controls
          </h2>
          <p className="mt-1 text-xs leading-5 text-slate-500">
            These settings are saved in this browser and are intended for the
            local broadcast operator workflow.
          </p>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Home accent
            </span>
            <input
              type="color"
              value={themeSettings.homeAccent}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    homeAccent: event.target.value,
                  }),
                )
              }
              className="h-10 w-full rounded-lg border border-slate-800 bg-slate-950 p-1"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Away accent
            </span>
            <input
              type="color"
              value={themeSettings.awayAccent}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    awayAccent: event.target.value,
                  }),
                )
              }
              className="h-10 w-full rounded-lg border border-slate-800 bg-slate-950 p-1"
            />
          </label>

          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Overlay density
            </span>
            <select
              value={themeSettings.density}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    density: event.target
                      .value as BroadcastOverlayThemeSettings["density"],
                  }),
                )
              }
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            >
              <option value="COMPACT">COMPACT</option>
              <option value="STANDARD">STANDARD</option>
              <option value="LARGE">LARGE</option>
            </select>
          </label>

          <label className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={themeSettings.showLogos}
              onChange={(event) =>
                setThemeSettings((current) =>
                  normalizeBroadcastOverlayThemeSettings({
                    ...current,
                    showLogos: event.target.checked,
                  }),
                )
              }
            />
            Show team logos
          </label>
        </div>
      </section>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Ready
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.ready ? "YES" : "NO"}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Can go live
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.canGoLive ? "YES" : "NO"}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
          <div className="text-xs uppercase tracking-wide text-slate-500">
            Overlay eligible
          </div>
          <div className="mt-2 text-xl font-bold text-slate-100">
            {summary.overlayEligible ? "YES" : "NO"}
          </div>
        </div>
      </div>
    </section>
  );
}
