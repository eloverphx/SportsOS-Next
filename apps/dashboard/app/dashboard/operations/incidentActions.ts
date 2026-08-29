"use server";

import { revalidatePath } from "next/cache";

type IncidentAction = "acknowledge" | "resolve";

export interface IncidentActionState {
  ok: boolean;
  message: string;
}

async function mutateIncident(
  action: IncidentAction,
  formData: FormData,
): Promise<IncidentActionState> {
  const enabled =
    process.env.SPORTSOS_OPERATIONS_DASHBOARD_ENABLED?.trim().toLowerCase() ===
    "true";
  if (!enabled) return { ok: false, message: "Operations Dashboard is disabled." };

  const token = process.env.SPORTSOS_OPERATIONS_STATUS_TOKEN?.trim() ?? "";
  if (token.length < 32) {
    return { ok: false, message: "Operations incident access is not configured." };
  }

  const incidentId = String(formData.get("incidentId") ?? "").trim();
  const actor = String(formData.get("actor") ?? "").trim();
  const note = String(formData.get("note") ?? "").trim();

  if (!incidentId) return { ok: false, message: "Incident ID is required." };
  if (!actor) return { ok: false, message: "Operator name is required." };

  const baseUrl =
    process.env.SPORTSOS_API_INTERNAL_URL?.trim().replace(/\/$/, "") ||
    "http://api:4001";

  try {
    const response = await fetch(
      `${baseUrl}/deployment/operations/incidents/${encodeURIComponent(incidentId)}/${action}`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        cache: "no-store",
        body: JSON.stringify({ actor, note: note || null }),
      },
    );

    if (!response.ok) {
      const body = (await response.json().catch(() => null)) as
        | { error?: { message?: string } }
        | null;
      return {
        ok: false,
        message: body?.error?.message ?? `Incident action failed with HTTP ${response.status}.`,
      };
    }

    revalidatePath("/dashboard/operations");
    return {
      ok: true,
      message: action === "acknowledge" ? "Incident acknowledged." : "Incident resolved.",
    };
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : "Incident action failed.",
    };
  }
}

// SPORTSOS_M34_7_SERVER_INCIDENT_ACTIONS
export async function acknowledgeIncidentAction(
  _previous: IncidentActionState,
  formData: FormData,
): Promise<IncidentActionState> {
  return mutateIncident("acknowledge", formData);
}

export async function resolveIncidentAction(
  _previous: IncidentActionState,
  formData: FormData,
): Promise<IncidentActionState> {
  return mutateIncident("resolve", formData);
}
