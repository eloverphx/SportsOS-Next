"use client";

import { useActionState } from "react";
import {
  acknowledgeIncidentAction,
  resolveIncidentAction,
  type IncidentActionState,
} from "./incidentActions";

const initialState: IncidentActionState = { ok: false, message: "" };

export function IncidentActions({
  incidentId,
  status,
}: {
  incidentId: string;
  status: "open" | "acknowledged" | "resolved";
}) {
  const [ackState, ackAction, ackPending] = useActionState(
    acknowledgeIncidentAction,
    initialState,
  );
  const [resolveState, resolveAction, resolvePending] = useActionState(
    resolveIncidentAction,
    initialState,
  );

  if (status === "resolved") {
    return <p className="mt-3 text-xs text-slate-500">Incident resolved.</p>;
  }

  return (
    // SPORTSOS_M34_7_INCIDENT_ACTION_CONTROLS
    <div className="mt-4 grid gap-3 lg:grid-cols-2">
      {status === "open" ? (
        <form action={ackAction} className="rounded border border-slate-800 p-3">
          <input type="hidden" name="incidentId" value={incidentId} />
          <label className="block text-xs text-slate-400">
            Operator
            <input
              required
              name="actor"
              autoComplete="name"
              className="mt-1 block w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-sm text-slate-200"
            />
          </label>
          <label className="mt-2 block text-xs text-slate-400">
            Note
            <input
              name="note"
              className="mt-1 block w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-sm text-slate-200"
            />
          </label>
          <button
            disabled={ackPending}
            className="mt-3 rounded border border-slate-600 px-3 py-1.5 text-sm text-slate-200 disabled:opacity-50"
          >
            {ackPending ? "Acknowledging…" : "Acknowledge"}
          </button>
          {ackState.message ? (
            <p className="mt-2 text-xs text-slate-400">{ackState.message}</p>
          ) : null}
        </form>
      ) : null}

      <form action={resolveAction} className="rounded border border-slate-800 p-3">
        <input type="hidden" name="incidentId" value={incidentId} />
        <label className="block text-xs text-slate-400">
          Operator
          <input
            required
            name="actor"
            autoComplete="name"
            className="mt-1 block w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-sm text-slate-200"
          />
        </label>
        <label className="mt-2 block text-xs text-slate-400">
          Resolution note
          <input
            name="note"
            className="mt-1 block w-full rounded border border-slate-700 bg-slate-950 px-2 py-1.5 text-sm text-slate-200"
          />
        </label>
        <button
          disabled={resolvePending}
          className="mt-3 rounded border border-slate-600 px-3 py-1.5 text-sm text-slate-200 disabled:opacity-50"
        >
          {resolvePending ? "Resolving…" : "Resolve"}
        </button>
        {resolveState.message ? (
          <p className="mt-2 text-xs text-slate-400">{resolveState.message}</p>
        ) : null}
      </form>
    </div>
  );
}
