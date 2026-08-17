"use client";

import { useMemo, useState } from "react";
import {
  buildBroadcastOperationsSummary,
} from "../../lib/tournament-broadcast-operations";
import { TournamentBroadcastOperatorPanel } from "./TournamentBroadcastOperatorPanel";

export function TournamentBroadcastOperationsDashboard() {
  const [gameId, setGameId] = useState("");
  const [sessionReady, setSessionReady] = useState(false);
  const [canGoLive, setCanGoLive] = useState(false);
  const [gameLive, setGameLive] = useState(false);
  const [transportLive, setTransportLive] = useState(false);
  const [overlayEligible, setOverlayEligible] = useState(false);
  const [realtimeConnected, setRealtimeConnected] = useState(false);

  const summary = useMemo(
    () =>
      buildBroadcastOperationsSummary({
        sessionReady,
        canGoLive,
        gameLive,
        transportLive,
        overlayEligible,
        realtimeConnected,
      }),
    [
      canGoLive,
      gameLive,
      overlayEligible,
      realtimeConnected,
      sessionReady,
      transportLive,
    ],
  );

  const overlayPath =
    gameId.trim().length > 0
      ? `/broadcast/overlay/${encodeURIComponent(gameId.trim())}`
      : null;

  return (
    <section
      data-testid="broadcast-operations-dashboard"
      className="space-y-6"
    >
      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Broadcast operations
            </div>

            <div className="mt-1 text-2xl font-bold text-slate-100">
              {summary.stage}
            </div>
          </div>

          <div className="text-right">
            <div className="text-3xl font-bold text-slate-100">
              {summary.progressPercent}%
            </div>
            <div className="text-xs text-slate-500">
              readiness
            </div>
          </div>
        </div>

        <div className="mt-4 h-2 overflow-hidden rounded-full bg-slate-900">
          <div
            className="h-full bg-slate-400 transition-all"
            style={{
              width: `${summary.progressPercent}%`,
            }}
          />
        </div>

        {summary.alerts.length > 0 ? (
          <div className="mt-4 grid gap-2 md:grid-cols-2">
            {summary.alerts.map((alert) => (
              <div
                key={alert}
                className="rounded-lg border border-amber-900/50 bg-amber-950/20 px-3 py-2 text-xs text-amber-200"
              >
                {alert}
              </div>
            ))}
          </div>
        ) : null}
      </div>

      <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-5">
        <div className="grid gap-4 lg:grid-cols-2">
          <label className="text-sm text-slate-300">
            <span className="mb-1 block text-xs uppercase tracking-wide text-slate-500">
              Game ID
            </span>
            <input
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="Enter game ID"
              className="w-full rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-slate-100"
            />
          </label>

          <div>
            <div className="mb-1 text-xs uppercase tracking-wide text-slate-500">
              Browser source
            </div>

            {overlayPath ? (
              <div className="flex gap-2">
                <code
                  data-testid="broadcast-overlay-url"
                  className="min-w-0 flex-1 overflow-x-auto rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-xs text-slate-300"
                >
                  {overlayPath}
                </code>

                <a
                  href={overlayPath}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-lg border border-slate-700 px-3 py-2 text-xs font-semibold text-slate-200"
                >
                  Open
                </a>
              </div>
            ) : (
              <div className="rounded-lg border border-slate-800 bg-slate-950 px-3 py-2 text-xs text-slate-500">
                Enter a game ID to generate the browser-source path.
              </div>
            )}
          </div>
        </div>
      </div>

      <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        {[
          ["Session ready", sessionReady, setSessionReady],
          ["Can go live", canGoLive, setCanGoLive],
          ["Game live", gameLive, setGameLive],
          ["Transport live", transportLive, setTransportLive],
          ["Overlay eligible", overlayEligible, setOverlayEligible],
          ["Realtime connected", realtimeConnected, setRealtimeConnected],
        ].map(([label, checked, setter]) => (
          <label
            key={String(label)}
            className="flex items-center gap-3 rounded-lg border border-slate-800 bg-slate-950/40 px-3 py-3 text-sm text-slate-300"
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

      <TournamentBroadcastOperatorPanel />
    </section>
  );
}
