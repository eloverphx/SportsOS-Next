"use client";

import { useEffect, useMemo, useState } from "react";
import { api } from "../../lib/api";
import {
  PERMISSIONS,
  getStoredUser,
  userHasPermission,
} from "../../lib/auth";
import type { ScheduleGame } from "../../lib/tournament-schedule";
import "./tournament-schedule-editor.css";

type FullGame = ScheduleGame & {
  readonly organizationId: number;
  readonly seasonId: number;
  readonly homeTeamId: number | null;
  readonly homeExternalName: string | null;
  readonly awayTeamId: number | null;
  readonly awayExternalName: string | null;
  readonly timezone: string;
  readonly homeScore: number;
  readonly awayScore: number;
  readonly regulationPeriods: number;
  readonly regulationPeriodLengthMs: number;
  readonly intermissionLengthMs: number;
  readonly overtimeEnabled: boolean;
  readonly overtimeLengthMs: number;
  readonly notes: string | null;
};

type SchedulePreviewConflict = {
  readonly code:
    | "RINK_OVERLAP"
    | "TEAM_OVERLAP"
    | "TEAM_TURNAROUND"
    | "MISSING_RINK";
  readonly severity: "ERROR" | "WARNING";
  readonly gameId: number;
  readonly relatedGameId: number | null;
  readonly message: string;
};

type SchedulePreviewResponse = {
  readonly gameId: number;
  readonly scheduledStart: string;
  readonly venue: string | null;
  readonly hardConflict: boolean;
  readonly conflicts: SchedulePreviewConflict[];
};

type Props = {
  readonly games: readonly ScheduleGame[];
  readonly onSaved: () => Promise<void> | void;
};

type Draft = {
  readonly gameId: number;
  readonly scheduledStart: string;
  readonly venue: string;
};

function toLocalDateTime(value: string): string {
  const date = new Date(value);
  const offsetMs = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offsetMs).toISOString().slice(0, 16);
}

export function TournamentScheduleEditor({ games, onSaved }: Props) {
  const user = getStoredUser();
  const canManage = userHasPermission(user, PERMISSIONS.GAME_MANAGE);

  const scheduledGames = useMemo(
    () => games.filter((game) => game.status === "SCHEDULED"),
    [games],
  );

  const [draft, setDraft] = useState<Draft | null>(null);
  const [preview, setPreview] = useState<SchedulePreviewResponse | null>(null);
  const [previewBusy, setPreviewBusy] = useState(false);
  const [previewError, setPreviewError] = useState("");
  const [overrideHardConflicts, setOverrideHardConflicts] = useState(false);
  const [scheduleOverrideReason, setScheduleOverrideReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const hardConflicts =
    preview?.conflicts.filter((conflict) => conflict.severity === "ERROR") ?? [];
  const warnings =
    preview?.conflicts.filter((conflict) => conflict.severity === "WARNING") ?? [];

  useEffect(() => {
    if (!draft || !canManage || !draft.scheduledStart) {
      setPreview(null);
      setPreviewError("");
      setPreviewBusy(false);
      return;
    }

    let cancelled = false;
    const timer = window.setTimeout(() => {
      setPreviewBusy(true);
      setPreviewError("");

      void api<SchedulePreviewResponse>(
        `/games/${draft.gameId}/schedule-preview`,
        {
          method: "POST",
          body: JSON.stringify({
            scheduledStart: new Date(draft.scheduledStart).toISOString(),
            venue: draft.venue.trim() || null,
          }),
        },
      )
        .then((response) => {
          if (cancelled) return;
          setPreview(response);
          setOverrideHardConflicts(false);
          setScheduleOverrideReason("");
        })
        .catch((caughtError) => {
          if (cancelled) return;
          setPreview(null);
          setPreviewError(
            caughtError instanceof Error
              ? caughtError.message
              : "Could not validate proposed schedule.",
          );
        })
        .finally(() => {
          if (!cancelled) setPreviewBusy(false);
        });
    }, 300);

    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [canManage, draft]);

  function begin(game: ScheduleGame): void {
    if (!canManage || game.status !== "SCHEDULED") return;

    setDraft({
      gameId: game.id,
      scheduledStart: toLocalDateTime(game.scheduledStart),
      venue: game.venue ?? "",
    });
    setPreview(null);
    setPreviewError("");
    setOverrideHardConflicts(false);
    setScheduleOverrideReason("");
    setError("");
    setSuccess("");
  }

  async function save(): Promise<void> {
    if (!draft || !canManage) return;

    if (!draft.scheduledStart) {
      setError("Scheduled start is required.");
      return;
    }

    if (!preview || previewBusy || previewError) {
      setError("Wait for server schedule validation before saving.");
      return;
    }

    if (preview.hardConflict && !overrideHardConflicts) {
      setError("Hard schedule conflicts must be resolved or explicitly overridden.");
      return;
    }

    if (
      preview.hardConflict &&
      overrideHardConflicts &&
      scheduleOverrideReason.trim().length === 0
    ) {
      setError("Enter a reason for overriding the hard schedule conflict.");
      return;
    }

    if (
      preview.hardConflict &&
      !window.confirm(
        `Override ${hardConflicts.length} hard schedule conflict${
          hardConflicts.length === 1 ? "" : "s"
        } and save anyway?`,
      )
    ) {
      return;
    }

    setBusy(true);
    setError("");
    setSuccess("");

    try {
      const response = await api<{ game: FullGame }>(`/games/${draft.gameId}`);
      const game = response.game;

      if (game.status !== "SCHEDULED") {
        throw new Error("Only scheduled games can be moved from Tournament Director.");
      }

      await api<{ game: FullGame }>(`/games/${draft.gameId}`, {
        method: "PUT",
        body: JSON.stringify({
          organizationId: game.organizationId,
          seasonId: game.seasonId,
          homeTeamId: game.homeTeamId,
          homeExternalName: game.homeTeamId ? null : game.homeExternalName,
          awayTeamId: game.awayTeamId,
          awayExternalName: game.awayTeamId ? null : game.awayExternalName,
          scheduledStart: new Date(draft.scheduledStart).toISOString(),
          timezone: game.timezone,
          venue: draft.venue.trim() || null,
          status: game.status,
          homeScore: game.homeScore,
          awayScore: game.awayScore,
          regulationPeriods: game.regulationPeriods,
          regulationPeriodLengthMs: game.regulationPeriodLengthMs,
          intermissionLengthMs: game.intermissionLengthMs,
          overtimeEnabled: game.overtimeEnabled,
          overtimeLengthMs: game.overtimeLengthMs,
          notes: game.notes,
          scheduleConflictOverride: overrideHardConflicts,
          scheduleConflictOverrideReason:
            scheduleOverrideReason.trim() || null,
        }),
      });

      setSuccess(`Game #${draft.gameId} schedule updated.`);
      setDraft(null);
      setPreview(null);
      setPreviewError("");
      setOverrideHardConflicts(false);
      setScheduleOverrideReason("");
      await onSaved();
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : "Could not update tournament schedule.",
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <section id="director-scheduling" data-testid="director-scheduling" className="scheduleEditorPanel" aria-labelledby="schedule-editor-heading">
      <div className="scheduleEditorHeader">
        <div>
          <span className="scheduleEditorEyebrow">Interactive scheduling</span>
          <h2 id="schedule-editor-heading">Move a scheduled game</h2>
          <p>
            Change rink and start time. Preview and final save are both validated
            by the authoritative server conflict engine.
          </p>
        </div>

        {!canManage ? (
          <span className="scheduleEditorReadOnly">Read-only</span>
        ) : null}
      </div>

      {error ? <div className="scheduleEditorError">{error}</div> : null}
      {success ? <div className="scheduleEditorSuccess">{success}</div> : null}

      {!canManage ? (
        <p className="scheduleEditorMuted">
          Your account does not have permission to manage game schedules.
        </p>
      ) : (
        <>
          <div className="scheduleGamePicker">
            {scheduledGames.length === 0 ? (
              <span className="scheduleEditorMuted">
                No scheduled games are available to move.
              </span>
            ) : (
              scheduledGames.map((game) => (
                <button
                  key={game.id}
                  type="button"
                  className={draft?.gameId === game.id ? "active" : ""}
                  onClick={() => begin(game)}
                >
                  <strong>#{game.id}</strong>
                  <span>
                    {game.homeTeamName} vs {game.awayTeamName}
                  </span>
                  <small>{game.venue || "Rink not assigned"}</small>
                </button>
              ))
            )}
          </div>

          {draft ? (
            <div className="scheduleEditorWorkspace">
              <div className="scheduleEditorFields">
                <label>
                  Start time
                  <input
                    type="datetime-local"
                    value={draft.scheduledStart}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        scheduledStart: event.target.value,
                      })
                    }
                  />
                </label>

                <label>
                  Rink / venue
                  <input
                    value={draft.venue}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        venue: event.target.value,
                      })
                    }
                    placeholder="Rink 1"
                  />
                </label>
              </div>

              <div className="schedulePreview">
                <div>
                  <span>Server validation</span>
                  <strong>
                    {previewBusy
                      ? "Checking…"
                      : previewError
                        ? "Unavailable"
                        : preview
                          ? "Current"
                          : "Pending"}
                  </strong>
                </div>
                <div>
                  <span>Hard conflicts</span>
                  <strong className={hardConflicts.length ? "bad" : "good"}>
                    {preview ? hardConflicts.length : "—"}
                  </strong>
                </div>
                <div>
                  <span>Warnings</span>
                  <strong>{preview ? warnings.length : "—"}</strong>
                </div>
              </div>

              {previewError ? (
                <div className="scheduleEditorError">{previewError}</div>
              ) : null}

              {preview && preview.conflicts.length > 0 ? (
                <div className="schedulePreviewConflicts">
                  {preview.conflicts.map((conflict, index) => (
                    <div
                      key={`${conflict.code}-${conflict.gameId}-${conflict.relatedGameId ?? "none"}-${index}`}
                      className={
                        conflict.severity === "ERROR"
                          ? "schedulePreviewError"
                          : "schedulePreviewWarning"
                      }
                    >
                      <strong>{conflict.code}</strong>
                      <span>{conflict.message}</span>
                    </div>
                  ))}
                </div>
              ) : preview && !previewBusy ? (
                <div className="schedulePreviewClean">
                  Server validation found no schedule conflicts.
                </div>
              ) : null}

              {preview?.hardConflict ? (
                <>
                  <label className="scheduleOverride">
                    <input
                      type="checkbox"
                      checked={overrideHardConflicts}
                      onChange={(event) => {
                        const checked = event.target.checked;
                        setOverrideHardConflicts(checked);
                        if (!checked) setScheduleOverrideReason("");
                      }}
                    />
                    I understand this change creates a hard tournament conflict and
                    want to override the block.
                  </label>

                  {overrideHardConflicts ? (
                    <label className="scheduleOverrideReason">
                      <span>Override reason</span>
                      <textarea
                        value={scheduleOverrideReason}
                        onChange={(event) =>
                          setScheduleOverrideReason(event.target.value)
                        }
                        maxLength={500}
                        rows={3}
                        required
                        placeholder="Explain why this hard conflict is being intentionally accepted."
                      />
                      <small>
                        Required for hard-conflict overrides. This reason is stored
                        in the audit trail.
                      </small>
                    </label>
                  ) : null}
                </>
              ) : null}

              <div className="scheduleEditorActions">
                <button
                  type="button"
                  className="secondary"
                  disabled={busy}
                  onClick={() => {
                    setDraft(null);
                    setPreview(null);
                    setPreviewError("");
                    setOverrideHardConflicts(false);
                    setScheduleOverrideReason("");
                    setError("");
                  }}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={
                    busy ||
                    previewBusy ||
                    !preview ||
                    Boolean(previewError) ||
                    (preview.hardConflict && !overrideHardConflicts)
                  }
                  onClick={() => void save()}
                >
                  {busy ? "Saving…" : "SAVE SCHEDULE CHANGE"}
                </button>
              </div>
            </div>
          ) : null}
        </>
      )}
    </section>
  );
}
