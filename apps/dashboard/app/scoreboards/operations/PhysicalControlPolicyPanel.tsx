"use client";

import {
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

type PolicyMode = "ENABLED" | "LOCKED";
type ScopeType = "GAME" | "DEVICE" | "GAME_DEVICE";

type Policy = {
  scopeType: ScopeType;
  gameId: string | null;
  deviceId: string | null;
  mode: PolicyMode;
  reason: string | null;
  updatedAt: string;
};

type IncidentResolution = {
  auditId: string;
  status:
    | "OPEN"
    | "ACKNOWLEDGED"
    | "RESOLVED";
  note: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  updatedAt: string;
};

type PhysicalControlIncident = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  inputId: string;
  inputType: string;
  sequence: number;
  disposition: string;
  error: string | null;
  createdAt: string;
};

type ReliabilityClassification = {
  deviceId: string;
  risk:
    | "HEALTHY"
    | "WATCH"
    | "AT_RISK"
    | "OFFLINE";
  availabilityPercent: number;
  degradedTransitions: number;
  readyTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  lastChangedAt: string;
  reasons: string[];
};

type ReadinessMetric = {
  deviceId: string;
  readyTransitions: number;
  degradedTransitions: number;
  currentState:
    | "READY"
    | "NOT_READY";
  firstObservedAt: string;
  lastChangedAt: string;
  lastObservedAt: string;
  readyMs: number;
  notReadyMs: number;
  availabilityPercent: number;
};

type ReadinessEvent = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  eventType:
    | "DEVICE_READINESS_DEGRADED"
    | "DEVICE_READINESS_RESTORED";
  disposition: string;
  error: string | null;
  createdAt: string;
};

type DeviceReadiness = {
  ready: boolean;
  deviceId: string;
  lastHeartbeatAt: string | null;
  heartbeatAgeMs: number | null;
  thresholdMs: number;
  reason: string | null;
};

type AssignedDevice = {
  gameId: string;
  deviceId: string;
};

type PhysicalControlHealth = {
  level:
    | "SAFE"
    | "RESTRICTED"
    | "EMERGENCY_LOCKED";
  acceptingPhysicalControls: boolean;
  emergencyLockActive: boolean;
  activePolicyCount: number;
  lockedPolicyCount: number;
  generatedAt: string;
  summary: string;
};

type EmergencyLock = {
  active: boolean;
  reason: string | null;
  actorUserId: string | null;
  actorRoles: string[];
  changedAt: string | null;
};

type PolicyAuditRecord = {
  auditId: string;
  action:
    | "SET"
    | "DELETE";
  actorUserId: string | null;
  actorRoles: string[];
  previousPolicy:
    Policy | null;
  nextPolicy:
    Policy | null;
  reason: string | null;
  createdAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function PhysicalControlPolicyPanel() {
  const [policies, setPolicies] = useState<Policy[]>([]);
  const [scopeType, setScopeType] = useState<ScopeType>("GAME_DEVICE");
  const [gameId, setGameId] = useState("");
  const [deviceId, setDeviceId] = useState("");
  const [mode, setMode] = useState<PolicyMode>("LOCKED");
  const [reason, setReason] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [incidentResolutions, setIncidentResolutions] =
    useState<IncidentResolution[]>([]);

  const [incidentNotes, setIncidentNotes] =
    useState<Record<string, string>>({});

  const [controlIncidents, setControlIncidents] =
    useState<PhysicalControlIncident[]>([]);

  const [
    reliabilityClassifications,
    setReliabilityClassifications,
  ] =
    useState<ReliabilityClassification[]>([]);

  const [readinessMetrics, setReadinessMetrics] =
    useState<ReadinessMetric[]>([]);

  const [readinessEvents, setReadinessEvents] =
    useState<ReadinessEvent[]>([]);

  const [deviceReadiness, setDeviceReadiness] =
    useState<DeviceReadiness[]>([]);

  const [assignedDevices, setAssignedDevices] =
    useState<AssignedDevice[]>([]);

  const [controlHealth, setControlHealth] =
    useState<PhysicalControlHealth | null>(null);

  const [emergencyLock, setEmergencyLock] =
    useState<EmergencyLock | null>(null);

  const [emergencyReason, setEmergencyReason] =
    useState("");

  const [auditRecords, setAuditRecords] =
    useState<PolicyAuditRecord[]>([]);

  const loadPolicies = useCallback(async () => {
    try {
      const [
        response,
        auditResponse,
        emergencyResponse,
        healthResponse,
        assignmentsResponse,
        incidentsResponse,
        readinessEventsResponse,
        readinessMetricsResponse,
        reliabilityResponse,
        incidentResolutionResponse,
      ] = await Promise.all([
        fetch(
          `${API_BASE}/scoreboard-control-policies`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-policy-audit?limit=25`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-emergency-lock`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-health`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-devices/assignments`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-incidents?limit=50`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-readiness-events?limit=50`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-readiness-metrics`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-readiness-reliability`,
          { cache: "no-store" },
        ),
        fetch(
          `${API_BASE}/scoreboard-control-incident-resolutions`,
          { cache: "no-store" },
        ),
      ]);

      if (!response.ok) {
        throw new Error(`Policy load failed (${response.status}).`);
      }

      const json = await response.json();
      const auditJson =
        auditResponse.ok
          ? await auditResponse.json()
          : null;

      setPolicies(json?.data?.policies ?? []);
      setAuditRecords(
        auditJson?.data?.records ?? [],
      );

      if (emergencyResponse.ok) {
        const emergencyJson =
          await emergencyResponse.json();

        setEmergencyLock(
          emergencyJson?.data?.emergencyLock ??
          null,
        );
      }

      if (healthResponse.ok) {
        const healthJson =
          await healthResponse.json();

        setControlHealth(
          healthJson?.data?.health ??
          null,
        );
      }

      if (assignmentsResponse.ok) {
        const assignmentsJson =
          await assignmentsResponse.json();

        const assignments =
          assignmentsJson?.data?.assignments ??
          assignmentsJson?.assignments ??
          [];

        setAssignedDevices(
          assignments,
        );

        const readinessResults =
          await Promise.all(
            assignments.map(
              async (
                assignment: AssignedDevice,
              ) => {
                try {
                  const readinessResponse =
                    await fetch(
                      `${API_BASE}/scoreboard-control-readiness/${encodeURIComponent(assignment.deviceId)}`,
                      {
                        cache: "no-store",
                      },
                    );

                  if (!readinessResponse.ok) {
                    return {
                      ready: false,
                      deviceId:
                        assignment.deviceId,
                      lastHeartbeatAt:
                        null,
                      heartbeatAgeMs:
                        null,
                      thresholdMs:
                        30000,
                      reason:
                        `Readiness request failed (${readinessResponse.status}).`,
                    } satisfies DeviceReadiness;
                  }

                  const readinessJson =
                    await readinessResponse.json();

                  return (
                    readinessJson?.data?.readiness ??
                    {
                      ready: false,
                      deviceId:
                        assignment.deviceId,
                      lastHeartbeatAt:
                        null,
                      heartbeatAgeMs:
                        null,
                      thresholdMs:
                        30000,
                      reason:
                        "Readiness response was empty.",
                    }
                  ) as DeviceReadiness;
                } catch {
                  return {
                    ready: false,
                    deviceId:
                      assignment.deviceId,
                    lastHeartbeatAt:
                      null,
                    heartbeatAgeMs:
                      null,
                    thresholdMs:
                      30000,
                    reason:
                      "Unable to query device readiness.",
                  } satisfies DeviceReadiness;
                }
              },
            ),
          );

        setDeviceReadiness(
          readinessResults,
        );
      }

      if (incidentsResponse.ok) {
        const incidentsJson =
          await incidentsResponse.json();

        setControlIncidents(
          incidentsJson?.data?.incidents ??
          [],
        );
      }

      if (readinessEventsResponse.ok) {
        const readinessEventsJson =
          await readinessEventsResponse.json();

        setReadinessEvents(
          readinessEventsJson?.data?.events ??
          [],
        );
      }

      if (readinessMetricsResponse.ok) {
        const readinessMetricsJson =
          await readinessMetricsResponse.json();

        setReadinessMetrics(
          readinessMetricsJson?.data?.metrics ??
          [],
        );
      }

      if (reliabilityResponse.ok) {
        const reliabilityJson =
          await reliabilityResponse.json();

        setReliabilityClassifications(
          reliabilityJson?.data?.devices ??
          [],
        );
      }

      if (incidentResolutionResponse.ok) {
        const resolutionJson =
          await incidentResolutionResponse.json();

        setIncidentResolutions(
          resolutionJson?.data?.resolutions ??
          [],
        );
      }
      setError(null);
    } catch (loadError) {
      setError(
        loadError instanceof Error
          ? loadError.message
          : "Unable to load physical control policies.",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadPolicies();
  }, [loadPolicies]);

  const scopeValid = useMemo(() => {
    if (scopeType === "GAME") return Boolean(gameId.trim());
    if (scopeType === "DEVICE") return Boolean(deviceId.trim());
    return Boolean(gameId.trim() && deviceId.trim());
  }, [scopeType, gameId, deviceId]);

  async function updateIncidentResolution(
    auditId: string,
    status:
      | "ACKNOWLEDGED"
      | "RESOLVED",
  ) {
    const note =
      incidentNotes[auditId]?.trim() ||
      "";

    if (
      status === "RESOLVED" &&
      !note
    ) {
      setError(
        "Enter a resolution note before resolving the incident.",
      );
      return;
    }

    setSaving(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-control-incidents/${encodeURIComponent(auditId)}`,
          {
            method: "PUT",
            headers: {
              "Content-Type":
                "application/json",
            },
            body:
              JSON.stringify({
                status,
                note:
                  note ||
                  null,
              }),
          },
        );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Incident update failed (${response.status}).`,
        );
      }

      setIncidentNotes(
        (current) => ({
          ...current,
          [auditId]: "",
        }),
      );

      setError(null);
      await loadPolicies();
    } catch (incidentError) {
      setError(
        incidentError instanceof Error
          ? incidentError.message
          : "Unable to update physical-control incident.",
      );
    } finally {
      setSaving(false);
    }
  }

  async function updateEmergencyLock(
    active: boolean,
  ) {
    if (
      active &&
      !emergencyReason.trim()
    ) {
      setError(
        "Enter a reason before activating the emergency lock.",
      );
      return;
    }

    setSaving(true);

    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-emergency-lock`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            active,
            reason:
              emergencyReason.trim() ||
              (
                active
                  ? null
                  : "Emergency lock cleared by operator."
              ),
          }),
        },
      );

      const json =
        await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Emergency lock update failed (${response.status}).`,
        );
      }

      setEmergencyReason("");
      setError(null);
      await loadPolicies();
    } catch (updateError) {
      setError(
        updateError instanceof Error
          ? updateError.message
          : "Unable to update emergency physical-control lock.",
      );
    } finally {
      setSaving(false);
    }
  }

  async function savePolicy(event: FormEvent) {
    event.preventDefault();

    if (!scopeValid) {
      setError("Complete the selected policy scope first.");
      return;
    }

    setSaving(true);

    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-policies`,
        {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scopeType,
            gameId: gameId.trim() || null,
            deviceId: deviceId.trim() || null,
            mode,
            reason: reason.trim() || null,
          }),
        },
      );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Policy update failed (${response.status}).`,
        );
      }

      setReason("");
      setError(null);
      await loadPolicies();
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to update physical control policy.",
      );
    } finally {
      setSaving(false);
    }
  }

  async function deletePolicy(policy: Policy) {
    setSaving(true);

    try {
      const response = await fetch(
        `${API_BASE}/scoreboard-control-policies`,
        {
          method: "DELETE",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scopeType: policy.scopeType,
            gameId: policy.gameId,
            deviceId: policy.deviceId,
          }),
        },
      );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Policy delete failed (${response.status}).`,
        );
      }

      setError(null);
      await loadPolicies();
    } catch (deleteError) {
      setError(
        deleteError instanceof Error
          ? deleteError.message
          : "Unable to delete physical control policy.",
      );
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div>
        <h2 className="text-xl font-semibold">
          Physical Control Lockout
        </h2>
        <p className="mt-1 text-sm text-slate-400">
          Server-authoritative enable/lock controls for physical scoreboard inputs.
        </p>
      </div>

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Physical Control Safety Status
            </h3>
            <p className="mt-1 text-sm text-slate-400">
              Server-authoritative status for physical scoreboard controls.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-semibold">
            {controlHealth?.level ?? "UNKNOWN"}
          </span>
        </div>

        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Global Input
            </div>
            <div className="mt-1 font-medium">
              {controlHealth
                ? controlHealth.acceptingPhysicalControls
                  ? "AVAILABLE"
                  : "BLOCKED"
                : "UNKNOWN"}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Locked Scopes
            </div>
            <div className="mt-1 font-medium">
              {controlHealth?.lockedPolicyCount ?? "—"}
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs text-slate-500">
              Emergency Lock
            </div>
            <div className="mt-1 font-medium">
              {controlHealth
                ? controlHealth.emergencyLockActive
                  ? "ACTIVE"
                  : "CLEAR"
                : "UNKNOWN"}
            </div>
          </div>
        </div>

        {controlHealth?.summary && (
          <p className="mt-3 text-sm text-slate-400">
            {controlHealth.summary}
          </p>
        )}
      </div>

      <div className="mt-5 rounded-xl border border-amber-800/60 bg-amber-950/20 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Emergency Physical Control Lock
            </h3>
            <p className="mt-1 text-sm text-slate-400">
              Immediately blocks all physical scoreboard button mutations.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-3 py-1 text-sm font-medium">
            {emergencyLock?.active
              ? "ACTIVE"
              : "CLEAR"}
          </span>
        </div>

        <input
          value={emergencyReason}
          onChange={(event) =>
            setEmergencyReason(
              event.target.value,
            )
          }
          placeholder={
            emergencyLock?.active
              ? "Reason for clearing lock"
              : "Required reason for emergency lock"
          }
          className="mt-4 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm"
        />

        <div className="mt-3 flex flex-wrap gap-2">
          {!emergencyLock?.active ? (
            <button
              type="button"
              disabled={saving}
              onClick={() =>
                void updateEmergencyLock(true)
              }
              className="rounded-lg border border-amber-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Activate Emergency Lock
            </button>
          ) : (
            <button
              type="button"
              disabled={saving}
              onClick={() =>
                void updateEmergencyLock(false)
              }
              className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
            >
              Clear Emergency Lock
            </button>
          )}
        </div>

        {emergencyLock?.active &&
          emergencyLock.reason && (
            <p className="mt-3 text-sm text-amber-200">
              Active reason: {emergencyLock.reason}
            </p>
          )}
      </div>

      <form
        onSubmit={savePolicy}
        className="mt-5 grid gap-4 lg:grid-cols-2"
      >
        <label className="grid gap-2 text-sm">
          <span className="text-slate-400">Scope</span>
          <select
            value={scopeType}
            onChange={(event) =>
              setScopeType(event.target.value as ScopeType)
            }
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="GAME">Game</option>
            <option value="DEVICE">Device</option>
            <option value="GAME_DEVICE">Game + Device</option>
          </select>
        </label>

        <label className="grid gap-2 text-sm">
          <span className="text-slate-400">Mode</span>
          <select
            value={mode}
            onChange={(event) =>
              setMode(event.target.value as PolicyMode)
            }
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="LOCKED">Locked</option>
            <option value="ENABLED">Enabled</option>
          </select>
        </label>

        {scopeType !== "DEVICE" && (
          <label className="grid gap-2 text-sm">
            <span className="text-slate-400">Game ID</span>
            <input
              value={gameId}
              onChange={(event) => setGameId(event.target.value)}
              placeholder="game-id"
              className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        )}

        {scopeType !== "GAME" && (
          <label className="grid gap-2 text-sm">
            <span className="text-slate-400">Device ID</span>
            <input
              value={deviceId}
              onChange={(event) => setDeviceId(event.target.value)}
              placeholder="scoreboard-device-id"
              className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        )}

        <label className="grid gap-2 text-sm lg:col-span-2">
          <span className="text-slate-400">Reason</span>
          <input
            value={reason}
            onChange={(event) => setReason(event.target.value)}
            placeholder="Optional operator note"
            className="rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <div className="lg:col-span-2">
          <button
            type="submit"
            disabled={saving || !scopeValid}
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50"
          >
            {saving
              ? "Saving…"
              : mode === "LOCKED"
                ? "Apply Lock"
                : "Apply Enable"}
          </button>
        </div>
      </form>

      {error && (
        <p className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </p>
      )}

      <div className="mt-6">
        <h3 className="font-semibold">Active Policies</h3>

        {loading ? (
          <p className="mt-3 text-sm text-slate-500">
            Loading policies…
          </p>
        ) : policies.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No explicit physical-control policies. Default behavior is enabled.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">Scope</th>
                  <th className="pb-2 pr-4">Game</th>
                  <th className="pb-2 pr-4">Device</th>
                  <th className="pb-2 pr-4">Mode</th>
                  <th className="pb-2 pr-4">Reason</th>
                  <th className="pb-2">Action</th>
                </tr>
              </thead>
              <tbody>
                {policies.map((policy) => (
                  <tr
                    key={[
                      policy.scopeType,
                      policy.gameId,
                      policy.deviceId,
                    ].join(":")}
                    className="border-t border-slate-800"
                  >
                    <td className="py-3 pr-4">{policy.scopeType}</td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {policy.gameId ?? "—"}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {policy.deviceId ?? "—"}
                    </td>
                    <td className="py-3 pr-4">{policy.mode}</td>
                    <td className="py-3 pr-4 text-slate-400">
                      {policy.reason ?? "—"}
                    </td>
                    <td className="py-3">
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() => void deletePolicy(policy)}
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Remove
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="mt-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div>
            <h3 className="font-semibold">
              Physical Control Incident Timeline
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Rejected or failed physical scoreboard inputs, newest first.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {controlIncidents.length} shown
          </span>
        </div>

        {controlIncidents.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No physical-control incidents recorded.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {controlIncidents.map(
              (incident) => {
                const resolutionForIncident =
                  incidentResolutions.find(
                    (item) =>
                      item.auditId ===
                      incident.auditId,
                  );

                return (
                <div
                  key={incident.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold">
                        {incident.disposition}
                      </span>
                      <span className="rounded border border-slate-800 px-2 py-0.5 font-mono text-xs">
                        {incident.inputType}
                      </span>
                    </div>

                    <span className="text-xs text-slate-500">
                      {incident.createdAt}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-1 text-slate-400 sm:grid-cols-2">
                    <div>
                      Device:{" "}
                      <span className="font-mono text-xs">
                        {incident.deviceId}
                      </span>
                    </div>
                    <div>
                      Game:{" "}
                      <span className="font-mono text-xs">
                        {incident.gameId ?? "unassigned"}
                      </span>
                    </div>
                    <div>
                      Sequence: {incident.sequence}
                    </div>
                    <div>
                      Input ID:{" "}
                      <span className="font-mono text-xs">
                        {incident.inputId}
                      </span>
                    </div>
                  </div>

                  {incident.error && (
                    <div className="mt-2 rounded border border-slate-800 bg-slate-950/50 p-2 text-slate-300">
                      {incident.error}
                    </div>
                  )}
                  <div className="mt-3 border-t border-slate-800 pt-3">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className="text-xs font-medium text-slate-400">
                        Status:{" "}
                        {resolutionForIncident?.status ?? "OPEN"}
                      </span>

                      {resolutionForIncident?.updatedAt && (
                        <span className="text-xs text-slate-500">
                          Updated {resolutionForIncident.updatedAt}
                        </span>
                      )}
                    </div>

                    <input
                      value={
                        incidentNotes[incident.auditId] ??
                        ""
                      }
                      onChange={(event) =>
                        setIncidentNotes(
                          (current) => ({
                            ...current,
                            [incident.auditId]:
                              event.target.value,
                          }),
                        )
                      }
                      placeholder="Acknowledgement or resolution note"
                      className="mt-2 w-full rounded border border-slate-800 bg-slate-950 px-3 py-2 text-xs"
                    />

                    <div className="mt-2 flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={saving}
                        onClick={() =>
                          void updateIncidentResolution(
                            incident.auditId,
                            "ACKNOWLEDGED",
                          )
                        }
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Acknowledge
                      </button>

                      <button
                        type="button"
                        disabled={saving}
                        onClick={() =>
                          void updateIncidentResolution(
                            incident.auditId,
                            "RESOLVED",
                          )
                        }
                        className="rounded border border-slate-700 px-2 py-1 text-xs disabled:opacity-50"
                      >
                        Resolve
                      </button>
                    </div>

                    {resolutionForIncident?.note && (
                      <p className="mt-2 text-xs text-slate-400">
                        Latest note: {resolutionForIncident.note}
                      </p>
                    )}
                  </div>
                </div>
                );
              },
            )}
          </div>
        )}
      </div>

      <div className="mt-6">
        <h3 className="font-semibold">
          Recent Policy Changes
        </h3>

        {auditRecords.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No policy changes recorded yet.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {auditRecords.map(
              (record) => (
                <div
                  key={record.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-medium">
                      {record.action}
                    </span>
                    <span className="text-xs text-slate-500">
                      {record.createdAt}
                    </span>
                  </div>

                  <div className="mt-1 text-slate-400">
                    Actor:{" "}
                    <span className="font-mono text-xs">
                      {record.actorUserId ?? "unknown"}
                    </span>
                  </div>

                  <div className="mt-1 text-slate-400">
                    Roles:{" "}
                    {record.actorRoles.length
                      ? record.actorRoles.join(", ")
                      : "unknown"}
                  </div>

                  {record.reason && (
                    <div className="mt-1 text-slate-400">
                      Reason: {record.reason}
                    </div>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Reliability Risk Classification
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Scoreboards are classified from server-side availability and degradation history.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {reliabilityClassifications.filter(
              (item) =>
                item.risk === "AT_RISK" ||
                item.risk === "OFFLINE",
            ).length}
            {" "}need attention
          </span>
        </div>

        {reliabilityClassifications.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No reliability history recorded yet.
          </p>
        ) : (
          <div className="mt-4 space-y-2">
            {reliabilityClassifications.map(
              (item) => (
                <div
                  key={item.deviceId}
                  className="rounded-lg border border-slate-800 p-3"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-mono text-xs">
                      {item.deviceId}
                    </span>
                    <span className="rounded border border-slate-700 px-2 py-1 text-xs font-semibold">
                      {item.risk}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-2 text-sm text-slate-400 sm:grid-cols-3">
                    <div>
                      Availability:{" "}
                      {item.availabilityPercent.toFixed(2)}%
                    </div>
                    <div>
                      Degraded:{" "}
                      {item.degradedTransitions}
                    </div>
                    <div>
                      State:{" "}
                      {item.currentState}
                    </div>
                  </div>

                  {item.reasons.length > 0 && (
                    <ul className="mt-2 list-disc space-y-1 pl-5 text-xs text-slate-500">
                      {item.reasons.map(
                        (reason) => (
                          <li key={reason}>
                            {reason}
                          </li>
                        ),
                      )}
                    </ul>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div>
          <h3 className="font-semibold">
            Device Reliability Metrics
          </h3>
          <p className="mt-1 text-sm text-slate-500">
            Long-lived readiness counters derived from server heartbeat observations.
          </p>
        </div>

        {readinessMetrics.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No readiness metrics recorded yet.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">Device</th>
                  <th className="pb-2 pr-4">State</th>
                  <th className="pb-2 pr-4">Availability</th>
                  <th className="pb-2 pr-4">Degraded</th>
                  <th className="pb-2 pr-4">Recovered</th>
                  <th className="pb-2">Last Change</th>
                </tr>
              </thead>
              <tbody>
                {readinessMetrics.map(
                  (metric) => (
                    <tr
                      key={metric.deviceId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 font-mono text-xs">
                        {metric.deviceId}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.currentState}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.availabilityPercent.toFixed(2)}%
                      </td>
                      <td className="py-3 pr-4">
                        {metric.degradedTransitions}
                      </td>
                      <td className="py-3 pr-4">
                        {metric.readyTransitions}
                      </td>
                      <td className="py-3 text-xs text-slate-400">
                        {metric.lastChangedAt}
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Readiness Recovery Timeline
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Device readiness degradation and restoration events.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {readinessEvents.length} events
          </span>
        </div>

        {readinessEvents.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No readiness transitions recorded yet.
          </p>
        ) : (
          <div className="mt-3 space-y-2">
            {readinessEvents.map(
              (event) => (
                <div
                  key={event.auditId}
                  className="rounded-lg border border-slate-800 p-3 text-sm"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <span className="font-semibold">
                      {event.eventType ===
                      "DEVICE_READINESS_RESTORED"
                        ? "RESTORED"
                        : "DEGRADED"}
                    </span>

                    <span className="text-xs text-slate-500">
                      {event.createdAt}
                    </span>
                  </div>

                  <div className="mt-2 grid gap-1 text-slate-400 sm:grid-cols-2">
                    <div>
                      Device:{" "}
                      <span className="font-mono text-xs">
                        {event.deviceId}
                      </span>
                    </div>
                    <div>
                      Game:{" "}
                      <span className="font-mono text-xs">
                        {event.gameId ?? "unassigned"}
                      </span>
                    </div>
                  </div>

                  {event.error && (
                    <p className="mt-2 text-xs text-slate-400">
                      {event.error}
                    </p>
                  )}
                </div>
              ),
            )}
          </div>
        )}
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold">
              Device Readiness Status
            </h3>
            <p className="mt-1 text-sm text-slate-500">
              Assigned scoreboard devices and their current heartbeat readiness.
            </p>
          </div>

          <span className="rounded border border-slate-700 px-2 py-1 text-xs">
            {deviceReadiness.filter(
              (item) => item.ready,
            ).length}
            /
            {assignedDevices.length}
            {" "}ready
          </span>
        </div>

        {assignedDevices.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No scoreboard devices are currently assigned.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Device
                  </th>
                  <th className="pb-2 pr-4">
                    Game
                  </th>
                  <th className="pb-2 pr-4">
                    Readiness
                  </th>
                  <th className="pb-2 pr-4">
                    Heartbeat Age
                  </th>
                  <th className="pb-2">
                    Detail
                  </th>
                </tr>
              </thead>
              <tbody>
                {assignedDevices.map(
                  (assignment) => {
                    const readiness =
                      deviceReadiness.find(
                        (item) =>
                          item.deviceId ===
                          assignment.deviceId,
                      );

                    return (
                      <tr
                        key={[
                          assignment.gameId,
                          assignment.deviceId,
                        ].join(":")}
                        className="border-t border-slate-800"
                      >
                        <td className="py-3 pr-4 font-mono text-xs">
                          {assignment.deviceId}
                        </td>
                        <td className="py-3 pr-4 font-mono text-xs">
                          {assignment.gameId}
                        </td>
                        <td className="py-3 pr-4">
                          {readiness
                            ? readiness.ready
                              ? "READY"
                              : "NOT READY"
                            : "CHECKING"}
                        </td>
                        <td className="py-3 pr-4">
                          {readiness?.heartbeatAgeMs != null
                            ? `${Math.round(
                                readiness.heartbeatAgeMs / 1000,
                              )}s`
                            : "—"}
                        </td>
                        <td className="py-3 text-slate-400">
                          {readiness?.reason ??
                            (
                              readiness?.lastHeartbeatAt
                                ? `Last heartbeat ${readiness.lastHeartbeatAt}`
                                : "—"
                            )}
                        </td>
                      </tr>
                    );
                  },
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <h3 className="font-semibold">
          Control Readiness Probe
        </h3>
        <p className="mt-1 text-sm text-slate-500">
          Physical mutations are accepted only while the server sees a recent scoreboard heartbeat.
        </p>
        <p className="mt-2 text-xs text-slate-500">
          Default readiness window: 30 seconds. Override with SPORTSOS_CONTROL_HEARTBEAT_MAX_AGE_MS.
        </p>
      </div>

      <div className="mt-6 rounded-xl border border-slate-800 p-4">
        <h3 className="font-semibold">
          Readiness Stability Window
        </h3>
        <p className="mt-1 text-sm text-slate-500">
          Readiness transitions must remain stable before SportsOS records degradation or recovery.
        </p>
        <p className="mt-2 text-xs text-slate-500">
          Default: 20 seconds. Configure with SPORTSOS_READINESS_STABILITY_WINDOW_MS.
        </p>
      </div>

      <p className="mt-5 text-xs text-slate-500">
        Dashboard state is informational only. The API policy store remains authoritative.
      </p>
    </section>
  );
}
