"use client";

import {
  useCallback,
  useEffect,
  useRef,
  useState,
} from "react";

type PreflightCheck = {
  id:
    | "COMMISSIONING"
    | "HEARTBEAT"
    | "RELIABILITY"
    | "SELF_TEST";
  passed: boolean;
  detail: string;
};

type PreflightFreshness = {
  fresh: boolean;
  expiresAt: string | null;
  ageMs: number | null;
  freshnessWindowMs: number;
  reason: string | null;
};

type GameDayHardwarePreflight = {
  preflightId: string;
  gameId: string;
  deviceId: string;
  status:
    | "PASS"
    | "FAIL";
  checks: PreflightCheck[];
  startedAt: string;
  completedAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function GameDayHardwarePreflightPanel() {
  const [gameId, setGameId] =
    useState("");

  const [latest, setLatest] =
    useState<GameDayHardwarePreflight | null>(
      null,
    );

  const [history, setHistory] =
    useState<GameDayHardwarePreflight[]>(
      [],
    );

  const [freshness, setFreshness] =
    useState<PreflightFreshness | null>(
      null,
    );

  const [busy, setBusy] =
    useState(false);

  const [
    autoRerunEnabled,
    setAutoRerunEnabled,
  ] =
    useState(true);

  const autoRerunInFlight =
    useRef(false);

  const [
    countdownNow,
    setCountdownNow,
  ] =
    useState(
      () => Date.now(),
    );

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const loadHistory =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        const normalized =
          targetGameId.trim();

        if (!normalized) {
          setLatest(
            null,
          );
          setHistory(
            [],
          );
          return;
        }

        const [
          latestResponse,
          historyResponse,
        ] =
          await Promise.all([
            fetch(
              `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}/latest`,
              {
                cache:
                  "no-store",
              },
            ),
            fetch(
              `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}/history`,
              {
                cache:
                  "no-store",
              },
            ),
          ]);

        if (
          latestResponse.ok
        ) {
          const json =
            await latestResponse.json();

          setLatest(
            json?.data?.preflight ??
            null,
          );

          setFreshness(
            json?.data?.freshness ??
            null,
          );
        }

        if (
          historyResponse.ok
        ) {
          const json =
            await historyResponse.json();

          setHistory(
            json?.data?.preflights ??
            [],
          );
        }
      },
      [],
    );

  const runPreflightSilently =
    useCallback(
      async (
        targetGameId: string,
      ) => {
        if (
          autoRerunInFlight.current
        ) {
          return;
        }

        autoRerunInFlight.current =
          true;

        try {
          const response =
            await fetch(
              `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(targetGameId)}`,
              {
                method:
                  "POST",
              },
            );

          const json =
            await response.json();

          if (
            json?.data?.preflight
          ) {
            setLatest(
              json.data.preflight,
            );
          }

          await loadHistory(
            targetGameId,
          );
        } finally {
          autoRerunInFlight.current =
            false;
        }
      },
      [
        loadHistory,
      ],
    );

  async function runPreflight() {
    const normalized =
      gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before running preflight.",
      );
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/game-day-hardware-preflight/${encodeURIComponent(normalized)}`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      const result =
        json?.data?.preflight ??
        null;

      if (result) {
        setLatest(
          result,
        );
      }

      if (!response.ok) {
        setError(
          json?.error ??
          `Preflight failed (${response.status}).`,
        );
      } else {
        setError(
          null,
        );
      }

      await loadHistory(
        normalized,
      );
    } catch (runError) {
      setError(
        runError instanceof Error
          ? runError.message
          : "Unable to run game-day hardware preflight.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  // Preflight auto-rerun loop
  useEffect(() => {
    const normalizedGameId =
      gameId.trim();

    if (
      !autoRerunEnabled ||
      !normalizedGameId ||
      !freshness?.fresh ||
      !freshness.expiresAt
    ) {
      return;
    }

    const remainingMs =
      Date.parse(
        freshness.expiresAt,
      ) -
      Date.now();

    if (
      remainingMs >
        120000 ||
      remainingMs <=
        0
    ) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void runPreflightSilently(
            normalizedGameId,
          );
        },
        1000,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    freshness,
    autoRerunEnabled,
    runPreflightSilently,
    countdownNow,
  ]);

  // Preflight countdown clock
  useEffect(() => {
    const timer =
      window.setInterval(
        () => {
          setCountdownNow(
            Date.now(),
          );
        },
        1000,
      );

  




  return () => {
      window.clearInterval(
        timer,
      );
    };
  }, []);

  useEffect(() => {
    const normalized =
      gameId.trim();

    if (!normalized) {
      return;
    }

    const timer =
      window.setTimeout(
        () => {
          void loadHistory(
            normalized,
          );
        },
        400,
      );

    return () => {
      window.clearTimeout(
        timer,
      );
    };
  }, [
    gameId,
    loadHistory,
  ]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Game-Day Hardware Preflight
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Run a fresh scoreboard readiness check for the selected game before start.
          </p>
        </div>

        {latest && (
          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {latest.status}
          </span>
        )}
      </div>

      <div className="mt-5 flex flex-col gap-3 sm:flex-row">
        <input
          value={gameId}
          onChange={(event) =>
            setGameId(
              event.target.value,
            )
          }
          placeholder="Game ID"
          className="min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />

        <button
          type="button"
          disabled={busy}
          onClick={() =>
            void runPreflight()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Run Game-Day Preflight
        </button>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Preflight Freshness
            </div>
            <div className="mt-1 text-xs text-slate-500">
              Passing preflight results are valid for a limited game-day window.
            </div>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
            {freshness?.fresh
              ? "FRESH"
              : "EXPIRED / REQUIRED"}
          </span>
        </div>

        <div className="mt-3 text-sm text-slate-400">
          {freshness?.reason ??
            (
              freshness?.expiresAt
                ? `Valid until ${freshness.expiresAt}`
                : "Run a game-day preflight."
            )}
        </div>

        {freshness?.ageMs != null && (
          <div className="mt-1 text-xs text-slate-500">
            Age:{" "}
            {Math.round(
              freshness.ageMs /
                1000,
            )}
            s
          </div>
        )}
      </div>

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Start Window Guidance
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Live countdown until the latest passing preflight expires.
            </p>
          </div>

          <button
            type="button"
            onClick={() =>
              setAutoRerunEnabled(
                (current) =>
                  !current,
              )
            }
            className="rounded border border-slate-700 px-3 py-1 text-xs font-medium"
          >
            Auto-Rerun:{" "}
            {autoRerunEnabled
              ? "ON"
              : "OFF"}
          </button>

          <span className="rounded border border-slate-700 px-3 py-1 font-mono text-sm font-semibold">
            {freshness?.expiresAt
              ? (() => {
                  const remainingSeconds =
                    Math.ceil(
                      Math.max(
                        0,
                        Date.parse(
                          freshness.expiresAt,
                        ) -
                          countdownNow,
                      ) /
                        1000,
                    );

                  const minutes =
                    Math.floor(
                      remainingSeconds /
                        60,
                    );

                  const seconds =
                    remainingSeconds %
                    60;

                  return `${String(
                    minutes,
                  ).padStart(
                    2,
                    "0",
                  )}:${String(
                    seconds,
                  ).padStart(
                    2,
                    "0",
                  )}`;
                })()
              : "--:--"}
          </span>
        </div>

        <p className="mt-2 text-xs text-slate-500">
          {autoRerunEnabled
            ? "Auto-rerun will refresh a fresh preflight when 2 minutes or less remain."
            : "Auto-rerun is paused; rerun manually before expiration."}
        </p>

        <p className="mt-3 text-sm text-slate-400">
          {!freshness
            ? "Run a game-day preflight before starting the game."
            : !freshness.fresh
              ? "Preflight is expired or invalid. Rerun it before game start."
              : freshness.expiresAt &&
                  Math.max(
                    0,
                    Date.parse(
                      freshness.expiresAt,
                    ) -
                      countdownNow,
                  ) <=
                    120000
                ? "Preflight is close to expiration. Rerun now to avoid a start delay."
                : freshness.expiresAt &&
                    Math.max(
                      0,
                      Date.parse(
                        freshness.expiresAt,
                      ) -
                        countdownNow,
                    ) <=
                      300000
                  ? "Preflight is still valid, but the start window is getting short."
                  : "Preflight is fresh and within the normal game-start window."}
        </p>

        {freshness?.fresh &&
          freshness.expiresAt && (
          <div className="mt-3 text-xs text-slate-500">
            Current passing preflight expires at{" "}
            {freshness.expiresAt}.
          </div>
        )}
      </div>
      {latest && (
        <div className="mt-5 rounded-xl border border-slate-800 p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="font-semibold">
                Latest Preflight
              </div>
              <div className="mt-1 text-xs text-slate-500">
                Device{" "}
                <span className="font-mono">
                  {latest.deviceId}
                </span>
              </div>
            </div>

            <div className="text-xs text-slate-500">
              {latest.completedAt}
            </div>
          </div>

          <div className="mt-4 grid gap-3 md:grid-cols-2">
            {latest.checks.map(
              (check) => (
                <div
                  key={check.id}
                  className="rounded-lg border border-slate-800 p-3"
                >
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-sm font-semibold">
                      {check.id}
                    </span>
                    <span className="rounded border border-slate-700 px-2 py-1 text-xs">
                      {check.passed
                        ? "PASS"
                        : "FAIL"}
                    </span>
                  </div>

                  <p className="mt-2 text-xs text-slate-500">
                    {check.detail}
                  </p>
                </div>
              ),
            )}
          </div>
        </div>
      )}

      {history.length > 0 && (
        <div className="mt-5 rounded-xl border border-slate-800 p-4">
          <div className="font-semibold">
            Preflight History
          </div>

          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Completed
                  </th>
                  <th className="pb-2 pr-4">
                    Device
                  </th>
                  <th className="pb-2 pr-4">
                    Result
                  </th>
                  <th className="pb-2">
                    Checks
                  </th>
                </tr>
              </thead>
              <tbody>
                {history.map(
                  (item) => (
                    <tr
                      key={item.preflightId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 text-xs text-slate-400">
                        {item.completedAt}
                      </td>
                      <td className="py-3 pr-4 font-mono text-xs">
                        {item.deviceId}
                      </td>
                      <td className="py-3 pr-4">
                        {item.status}
                      </td>
                      <td className="py-3 text-xs text-slate-400">
                        {item.checks.filter(
                          (check) =>
                            check.passed,
                        ).length}
                        /
                        {item.checks.length}
                        {" "}passed
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </section>
  );
}
