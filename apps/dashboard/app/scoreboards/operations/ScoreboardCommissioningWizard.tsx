"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

type CommissioningStepId =
  | "FLASHED"
  | "PROVISIONED"
  | "ENROLLED"
  | "VERIFIED"
  | "ASSIGNED"
  | "CONNECTIVITY"
  | "READINESS"
  | "FIRMWARE"
  | "GAME_READY";

type CommissioningStep = {
  id: CommissioningStepId;
  complete: boolean;
  completedAt: string | null;
  note: string | null;
};

type CommissioningRecord = {
  deviceId: string;
  createdAt: string;
  updatedAt: string;
  status:
    | "IN_PROGRESS"
    | "BLOCKED"
    | "GAME_READY";
  steps: CommissioningStep[];
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

const COMMISSIONING_AUTO_REFRESH_MS =
  5000;

const STEP_LABELS:
  Record<
    CommissioningStepId,
    string
  > = {
    FLASHED:
      "Firmware Flashed",
    PROVISIONED:
      "Device Provisioned",
    ENROLLED:
      "SportsOS Enrollment",
    VERIFIED:
      "Verified Hardware",
    ASSIGNED:
      "Scoreboard Assignment",
    CONNECTIVITY:
      "Connectivity",
    READINESS:
      "Heartbeat Readiness",
    FIRMWARE:
      "Approved Firmware",
    GAME_READY:
      "Game Ready",
  };

export function ScoreboardCommissioningWizard() {
  const [deviceId, setDeviceId] =
    useState("");

  const [
    commissioning,
    setCommissioning,
  ] =
    useState<CommissioningRecord | null>(
      null,
    );

  const [busy, setBusy] =
    useState(false);

  const [
    autoRefreshEnabled,
    setAutoRefreshEnabled,
  ] =
    useState(true);

  const validationInFlight =
    useRef(false);

  const [error, setError] =
    useState<string | null>(
      null,
    );

  const completedCount =
    useMemo(
      () =>
        commissioning?.steps.filter(
          (step) =>
            step.complete,
        ).length ??
        0,
      [commissioning],
    );

  const loadRecord =
    useCallback(
      async (
        requestedDeviceId:
          string,
      ) => {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(requestedDeviceId)}`,
            {
              cache:
                "no-store",
            },
          );

        if (!response.ok) {
          throw new Error(
            `Commissioning load failed (${response.status}).`,
          );
        }

        const json =
          await response.json();

        const record =
          json?.data?.commissioning ??
          null;

        setCommissioning(
          record,
        );

        return record as
          | CommissioningRecord
          | null;
      },
      [],
    );

  async function startCommissioning() {
    const normalized =
      deviceId.trim();

    if (!normalized) {
      setError(
        "Enter a scoreboard device ID.",
      );
      return;
    }

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(normalized)}`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Commissioning start failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (startError) {
      setError(
        startError instanceof Error
          ? startError.message
          : "Unable to start commissioning.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function setManualStep(
    step:
      | "FLASHED"
      | "PROVISIONED",
    complete:
      boolean,
  ) {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(commissioning.deviceId)}/step`,
          {
            method:
              "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                step,
                complete,
                note:
                  complete
                    ? "Confirmed by installer."
                    : "Installer confirmation cleared.",
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Step update failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (stepError) {
      setError(
        stepError instanceof Error
          ? stepError.message
          : "Unable to update commissioning step.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  const validateCommissioningSilently =
    useCallback(
      async (
        targetDeviceId:
          string,
      ) => {
        if (
          validationInFlight.current
        ) {
          return;
        }

        validationInFlight.current =
          true;

        try {
          const response =
            await fetch(
              `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(targetDeviceId)}/validate`,
              {
                method:
                  "POST",
              },
            );

          if (!response.ok) {
            return;
          }

          const json =
            await response.json();

          setCommissioning(
            json?.data?.commissioning ??
            null,
          );
        } finally {
          validationInFlight.current =
            false;
        }
      },
      [],
    );

  async function runValidation() {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-device-commissioning/${encodeURIComponent(commissioning.deviceId)}/validate`,
          {
            method:
              "POST",
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Validation failed (${response.status}).`,
        );
      }

      setCommissioning(
        json?.data?.commissioning ??
        null,
      );

      setError(
        null,
      );
    } catch (validationError) {
      setError(
        validationError instanceof Error
          ? validationError.message
          : "Unable to validate commissioning.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  async function refresh() {
    if (!commissioning) {
      return;
    }

    setBusy(
      true,
    );

    try {
      await loadRecord(
        commissioning.deviceId,
      );

      setError(
        null,
      );
    } catch (refreshError) {
      setError(
        refreshError instanceof Error
          ? refreshError.message
          : "Unable to refresh commissioning record.",
      );
    } finally {
      setBusy(
        false,
      );
    }
  }

  // Commissioning live progress loop
  useEffect(() => {
    if (
      !commissioning ||
      commissioning.status ===
        "GAME_READY" ||
      !autoRefreshEnabled
    ) {
      return;
    }

    const device =
      commissioning.deviceId;

    const timer =
      window.setInterval(
        () => {
          void validateCommissioningSilently(
            device,
          );
        },
        COMMISSIONING_AUTO_REFRESH_MS,
      );

    return () => {
      window.clearInterval(
        timer,
      );
    };
  }, [
    commissioning,
    autoRefreshEnabled,
    validateCommissioningSilently,
  ]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Scoreboard Commissioning
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Guided installation workflow from flashed controller to GAME_READY.
          </p>
        </div>

        {commissioning && (
          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {commissioning.status}
          </span>
        )}
      </div>

      {!commissioning ? (
        <div className="mt-5 flex flex-col gap-3 sm:flex-row">
          <input
            value={deviceId}
            onChange={(event) =>
              setDeviceId(
                event.target.value,
              )
            }
            placeholder="Scoreboard device ID"
            className="min-w-0 flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />

          <button
            type="button"
            disabled={busy}
            onClick={() =>
              void startCommissioning()
            }
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            Start Commissioning
          </button>
        </div>
      ) : (
        <>
          <div className="mt-5 flex flex-wrap items-center justify-between gap-3 rounded-lg border border-slate-800 p-4">
            <div>
              <div className="text-xs text-slate-500">
                Device
              </div>
              <div className="mt-1 font-mono text-sm">
                {commissioning.deviceId}
              </div>
            </div>

            <div className="text-sm text-slate-400">
              {completedCount}
              /
              {commissioning.steps.length}
              {" "}steps complete
            </div>

            <div className="text-xs text-slate-500">
              {commissioning.status ===
                "GAME_READY"
                ? "Auto-validation complete."
                : autoRefreshEnabled
                  ? "Auto-validation every 5 seconds."
                  : "Auto-validation paused."}
            </div>

            <div className="flex flex-wrap items-center gap-2">
              <button
                type="button"
                onClick={() =>
                  setAutoRefreshEnabled(
                    (current) =>
                      !current,
                  )
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs"
              >
                Live Progress:{" "}
                {autoRefreshEnabled
                  ? "ON"
                  : "OFF"}
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void refresh()
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs disabled:opacity-50"
              >
                Refresh
              </button>

              <button
                type="button"
                disabled={busy}
                onClick={() =>
                  void runValidation()
                }
                className="rounded border border-slate-700 px-3 py-2 text-xs font-medium disabled:opacity-50"
              >
                Run Validation
              </button>
            </div>
          </div>

          <div className="mt-4 space-y-2">
            {commissioning.steps.map(
              (step) => (
                <div
                  key={step.id}
                  className="rounded-lg border border-slate-800 p-4"
                >
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                      <div className="font-medium">
                        {STEP_LABELS[step.id]}
                      </div>
                      <div className="mt-1 text-xs text-slate-500">
                        {step.id}
                      </div>
                    </div>

                    <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
                      {step.complete
                        ? "PASS"
                        : "PENDING"}
                    </span>
                  </div>

                  {step.note && (
                    <p className="mt-2 text-sm text-slate-400">
                      {step.note}
                    </p>
                  )}

                  {step.completedAt && (
                    <p className="mt-1 text-xs text-slate-500">
                      Completed {step.completedAt}
                    </p>
                  )}

                  {(step.id ===
                    "FLASHED" ||
                    step.id ===
                      "PROVISIONED") && (
                    <div className="mt-3 flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={
                          busy ||
                          step.complete
                        }
                        onClick={() =>
                          void setManualStep(
                            step.id as
                              | "FLASHED"
                              | "PROVISIONED",
                            true,
                          )
                        }
                        className="rounded border border-slate-700 px-3 py-1 text-xs disabled:opacity-50"
                      >
                        Confirm Complete
                      </button>

                      <button
                        type="button"
                        disabled={
                          busy ||
                          !step.complete
                        }
                        onClick={() =>
                          void setManualStep(
                            step.id as
                              | "FLASHED"
                              | "PROVISIONED",
                            false,
                          )
                        }
                        className="rounded border border-slate-800 px-3 py-1 text-xs disabled:opacity-50"
                      >
                        Clear
                      </button>
                    </div>
                  )}
                </div>
              ),
            )}
          </div>

          {commissioning.status ===
            "GAME_READY" && (
            <div className="mt-5 rounded-xl border border-slate-700 p-5">
              <div className="text-lg font-semibold">
                GAME_READY
              </div>
              <p className="mt-1 text-sm text-slate-400">
                This scoreboard controller has passed the full commissioning workflow.
              </p>
            </div>
          )}

          <button
            type="button"
            disabled={busy}
            onClick={() => {
              setCommissioning(
                null,
              );
              setDeviceId(
                "",
              );
              setError(
                null,
              );
            }}
            className="mt-4 rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-50"
          >
            Commission Another Device
          </button>
        </>
      )}

      {error && (
        <p className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </p>
      )}
    </section>
  );
}
