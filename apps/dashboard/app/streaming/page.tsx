"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";
import { getStoredUser, PERMISSIONS, userHasPermission } from "../../lib/auth";

type RecordingStatus = "CREATED" | "RECORDING" | "PROCESSING" | "READY" | "FAILED" | "ARCHIVED";

type RecordingSource = "LIVE" | "UPLOAD" | "IMPORT";

interface Recording {
  readonly id: number;
  readonly organizationId: number;
  readonly gameId: number | null;
  readonly ownerUserId: number | null;
  readonly mediaAssetId: number | null;
  readonly source: RecordingSource;
  readonly status: RecordingStatus;
  readonly title: string | null;
  readonly startedAt: string | null;
  readonly endedAt: string | null;
  readonly durationMs: number | null;
  readonly publishedAt: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
  readonly mediaUrl: string | null;
}

interface EventAnchor {
  readonly id: number;
  readonly recordingId: number;
  readonly gameEventId: number;
  readonly recordingOffsetMs: number;
  readonly anchorSource: "SCOREKEEPER" | "SYSTEM";
  readonly eventType: "GOAL" | "PENALTY";
  readonly side: "home" | "away";
  readonly period: number;
  readonly clockRemainingMs: number;
  readonly playerId: number | null;
  readonly playerName: string | null;
  readonly playerJerseyNumber: number | null;
  readonly assist1PlayerId: number | null;
  readonly assist2PlayerId: number | null;
  readonly voidedAt: string | null;
  readonly eventCreatedAt: string;
  readonly eligibleForHighlights: boolean;
  readonly suggestedClipWindow: {
    readonly startMs: number;
    readonly endMs: number;
    readonly durationMs: number;
  };
}

type ClipJobStatus = "PENDING" | "PROCESSING" | "READY" | "FAILED" | "CANCELLED";

interface ClipJob {
  readonly id: number;
  readonly organizationId: number;
  readonly recordingId: number;
  readonly gameEventId: number;
  readonly requestedByUserId: number;
  readonly selectionSource: "SCOREKEEPER_EVENT" | "AI_SELECTION";
  readonly startMs: number;
  readonly endMs: number;
  readonly durationMs: number;
  readonly status: ClipJobStatus;
  readonly outputMediaAssetId: number | null;
  readonly errorMessage: string | null;
  readonly attemptCount: number;
  readonly claimedAt: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

interface RecordingsResponse {
  readonly recordings: Recording[];
}

interface AnchorsResponse {
  readonly recordingId: number;
  readonly anchors: EventAnchor[];
}

interface ClipJobsResponse {
  readonly recordingId: number;
  readonly clipJobs: ClipJob[];
}

interface CreateClipJobResponse {
  readonly clipJob: ClipJob;
}

interface PlaybackSessionResponse {
  readonly playbackUrl: string;
  readonly expiresAt: string;
}

type StatusFilter = "ALL" | RecordingStatus;

const STATUS_FILTERS: readonly StatusFilter[] = [
  "ALL",
  "RECORDING",
  "PROCESSING",
  "READY",
  "FAILED",
  "ARCHIVED",
];

function formatDuration(durationMs: number | null): string {
  if (durationMs == null) return "—";

  const totalSeconds = Math.max(0, Math.round(durationMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    : `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function formatClock(clockRemainingMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(clockRemainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

function formatDate(value: string | null): string {
  if (!value) return "—";
  return new Date(value).toLocaleString();
}

function statusClasses(status: RecordingStatus): string {
  switch (status) {
    case "READY":
      return "border-emerald-500/30 bg-emerald-500/10 text-emerald-300";
    case "RECORDING":
      return "border-red-500/30 bg-red-500/10 text-red-300";
    case "PROCESSING":
      return "border-amber-500/30 bg-amber-500/10 text-amber-300";
    case "FAILED":
      return "border-rose-500/30 bg-rose-500/10 text-rose-300";
    case "ARCHIVED":
      return "border-slate-500/30 bg-slate-500/10 text-slate-300";
    default:
      return "border-sky-500/30 bg-sky-500/10 text-sky-300";
  }
}

export default function StreamingPage() {
  const [recordings, setRecordings] = useState<Recording[]>([]);
  const [filter, setFilter] = useState<StatusFilter>("ALL");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState("");
  const [playbackUrl, setPlaybackUrl] = useState<string | null>(null);
  const [playingRecordingId, setPlayingRecordingId] = useState<number | null>(null);
  const [playbackBusyId, setPlaybackBusyId] = useState<number | null>(null);
  const [operationsRecordingId, setOperationsRecordingId] = useState<number | null>(null);
  const [anchors, setAnchors] = useState<EventAnchor[]>([]);
  const [clipJobs, setClipJobs] = useState<ClipJob[]>([]);
  const [operationsLoading, setOperationsLoading] = useState(false);
  const [clipBusyEventId, setClipBusyEventId] = useState<number | null>(null);
  const [clipPlaybackBusyId, setClipPlaybackBusyId] = useState<number | null>(null);

  const canManageStreaming = userHasPermission(getStoredUser(), PERMISSIONS.STREAM_MANAGE);

  const loadRecordings = useCallback(async (background = false) => {
    if (background) {
      setRefreshing(true);
    } else {
      setLoading(true);
    }

    try {
      const result = await api<RecordingsResponse>("/recordings?limit=100");
      setRecordings(result.recordings);
      setError("");
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Unable to load streaming recordings.",
      );
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  const loadOperations = useCallback(async (recordingId: number, quiet = false) => {
    if (!quiet) setOperationsLoading(true);

    try {
      const [anchorResult, jobsResult] = await Promise.all([
        api<AnchorsResponse>(`/recordings/${recordingId}/event-anchors`),
        api<ClipJobsResponse>(`/recordings/${recordingId}/clip-jobs`),
      ]);
      setAnchors(anchorResult.anchors);
      setClipJobs(jobsResult.clipJobs);
      setError("");
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Unable to load highlight operations.",
      );
    } finally {
      if (!quiet) setOperationsLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadRecordings();

    const timer = window.setInterval(() => {
      void loadRecordings(true);
    }, 30_000);

    return () => window.clearInterval(timer);
  }, [loadRecordings]);

  useEffect(() => {
    if (operationsRecordingId == null) return;
    const timer = window.setInterval(() => {
      void loadOperations(operationsRecordingId, true);
    }, 5_000);
    return () => window.clearInterval(timer);
  }, [loadOperations, operationsRecordingId]);

  async function openPlayback(recording: Recording): Promise<void> {
    if (recording.status !== "READY" || recording.mediaAssetId == null) return;

    setPlaybackBusyId(recording.id);
    setError("");

    try {
      const session = await api<PlaybackSessionResponse>(
        `/media/assets/${recording.mediaAssetId}/playback-session`,
        {
          method: "POST",
          credentials: "include",
        },
      );

      setPlayingRecordingId(recording.id);
      setPlaybackUrl(`${API}${session.playbackUrl}`);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Unable to start recording playback.",
      );
    } finally {
      setPlaybackBusyId(null);
    }
  }

  async function openHighlightOperations(recordingId: number): Promise<void> {
    if (operationsRecordingId === recordingId) {
      setOperationsRecordingId(null);
      setAnchors([]);
      setClipJobs([]);
      return;
    }

    setOperationsRecordingId(recordingId);
    setAnchors([]);
    setClipJobs([]);
    await loadOperations(recordingId);
  }

  async function queueClip(anchor: EventAnchor): Promise<void> {
    if (operationsRecordingId == null || !anchor.eligibleForHighlights) return;

    setClipBusyEventId(anchor.gameEventId);
    setError("");

    try {
      const result = await api<CreateClipJobResponse>(
        `/recordings/${operationsRecordingId}/event-anchors/${anchor.gameEventId}/clip-jobs`,
        { method: "POST" },
      );
      setClipJobs((current) => [
        result.clipJob,
        ...current.filter((job) => job.id !== result.clipJob.id),
      ]);
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Unable to queue clip job.");
    } finally {
      setClipBusyEventId(null);
    }
  }

  async function openClipPlayback(job: ClipJob): Promise<void> {
    if (job.outputMediaAssetId == null) return;
    setClipPlaybackBusyId(job.id);
    setError("");

    try {
      const session = await api<PlaybackSessionResponse>(
        `/media/assets/${job.outputMediaAssetId}/playback-session`,
        { method: "POST", credentials: "include" },
      );
      setPlayingRecordingId(job.recordingId);
      setPlaybackUrl(`${API}${session.playbackUrl}`);
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : "Unable to start clip playback.",
      );
    } finally {
      setClipPlaybackBusyId(null);
    }
  }

  const filteredRecordings = useMemo(
    () => recordings.filter((recording) => filter === "ALL" || recording.status === filter),
    [filter, recordings],
  );

  const counts = useMemo(
    () => ({
      live: recordings.filter((recording) => recording.status === "RECORDING").length,
      processing: recordings.filter((recording) => recording.status === "PROCESSING").length,
      ready: recordings.filter((recording) => recording.status === "READY").length,
      failed: recordings.filter((recording) => recording.status === "FAILED").length,
    }),
    [recordings],
  );

  return (
    <AuthGate>
      <AppShell>
        <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                SportsOS Streaming
              </div>
              <h1 className="mt-2 text-3xl font-bold text-slate-100">Recordings</h1>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                Monitor recording lifecycle, securely play archives, and turn authoritative
                scorekeeper events into durable highlight clips.
              </p>
            </div>

            <button
              type="button"
              className="secondary self-start sm:self-auto"
              disabled={refreshing}
              onClick={() => void loadRecordings(true)}
            >
              {refreshing ? "Refreshing…" : "Refresh"}
            </button>
          </div>

          <div className="mt-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-xs uppercase tracking-wide text-slate-500">Live recording</div>
              <div className="mt-2 text-3xl font-bold text-slate-100">{counts.live}</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-xs uppercase tracking-wide text-slate-500">Processing</div>
              <div className="mt-2 text-3xl font-bold text-slate-100">{counts.processing}</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-xs uppercase tracking-wide text-slate-500">Ready archives</div>
              <div className="mt-2 text-3xl font-bold text-slate-100">{counts.ready}</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="text-xs uppercase tracking-wide text-slate-500">Failed</div>
              <div className="mt-2 text-3xl font-bold text-slate-100">{counts.failed}</div>
            </div>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            {STATUS_FILTERS.map((status) => (
              <button
                key={status}
                type="button"
                className={filter === status ? "" : "secondary"}
                onClick={() => setFilter(status)}
              >
                {status === "ALL" ? "All" : status.toLowerCase()}
              </button>
            ))}
          </div>

          {error && (
            <div
              role="alert"
              className="mt-6 rounded-xl border border-rose-500/30 bg-rose-500/10 p-4 text-sm text-rose-200"
            >
              {error}
            </div>
          )}

          <section className="mt-6 space-y-3">
            {loading ? (
              <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-6 text-slate-400">
                Loading recordings…
              </div>
            ) : filteredRecordings.length === 0 ? (
              <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-6 text-slate-400">
                No recordings match this view.
              </div>
            ) : (
              filteredRecordings.map((recording) => (
                <article
                  key={recording.id}
                  className="rounded-xl border border-slate-800 bg-slate-950/40 p-5"
                >
                  <div className="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <h2 className="text-lg font-semibold text-slate-100">
                          {recording.title ?? `Recording ${recording.id}`}
                        </h2>
                        <span
                          className={`rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClasses(recording.status)}`}
                        >
                          {recording.status}
                        </span>
                        <span className="rounded-full border border-slate-700 px-2.5 py-1 text-xs text-slate-400">
                          {recording.source}
                        </span>
                      </div>

                      <div className="mt-4 grid gap-x-8 gap-y-3 text-sm sm:grid-cols-2 xl:grid-cols-4">
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">Game</div>
                          <div className="mt-1 text-slate-200">
                            {recording.gameId == null ? "Not linked" : `#${recording.gameId}`}
                          </div>
                        </div>
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            Duration
                          </div>
                          <div className="mt-1 text-slate-200">
                            {formatDuration(recording.durationMs)}
                          </div>
                        </div>
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            Started
                          </div>
                          <div className="mt-1 text-slate-200">
                            {formatDate(recording.startedAt ?? recording.createdAt)}
                          </div>
                        </div>
                        <div>
                          <div className="text-xs uppercase tracking-wide text-slate-500">
                            Media
                          </div>
                          <div className="mt-1 text-slate-200">
                            {recording.mediaAssetId == null
                              ? "Not attached"
                              : `Asset #${recording.mediaAssetId}`}
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="flex shrink-0 flex-col items-end gap-2">
                      <div className="text-xs text-slate-500">Recording #{recording.id}</div>
                      {recording.status === "READY" && recording.mediaAssetId != null && (
                        <>
                          <button
                            type="button"
                            className="secondary"
                            disabled={playbackBusyId === recording.id}
                            onClick={() => void openPlayback(recording)}
                          >
                            {playbackBusyId === recording.id ? "Opening…" : "Play recording"}
                          </button>
                          <button
                            type="button"
                            className="secondary"
                            onClick={() => void openHighlightOperations(recording.id)}
                          >
                            {operationsRecordingId === recording.id
                              ? "Close highlights"
                              : "Highlights"}
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                </article>
              ))
            )}
          </section>

          {operationsRecordingId != null && (
            <section className="mt-6 rounded-xl border border-slate-800 bg-slate-950/40 p-5">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Authoritative event clips
                  </div>
                  <h2 className="mt-1 text-xl font-semibold text-slate-100">
                    Recording #{operationsRecordingId}
                  </h2>
                  <p className="mt-2 text-sm text-slate-400">
                    Scorekeeper/system anchors define clip timing. Voided events are excluded.
                  </p>
                </div>
                <button
                  type="button"
                  className="secondary"
                  disabled={operationsLoading}
                  onClick={() => void loadOperations(operationsRecordingId)}
                >
                  {operationsLoading ? "Refreshing…" : "Refresh clips"}
                </button>
              </div>

              {operationsLoading ? (
                <div className="mt-5 text-sm text-slate-400">Loading event anchors and jobs…</div>
              ) : anchors.length === 0 ? (
                <div className="mt-5 rounded-lg border border-slate-800 p-4 text-sm text-slate-400">
                  No authoritative recording event anchors are available.
                </div>
              ) : (
                <div className="mt-5 space-y-3">
                  {anchors.map((anchor) => {
                    const eventJobs = clipJobs.filter(
                      (job) => job.gameEventId === anchor.gameEventId,
                    );

                    return (
                      <article
                        key={anchor.id}
                        className="rounded-lg border border-slate-800 bg-slate-950/60 p-4"
                      >
                        <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                          <div>
                            <div className="font-medium text-slate-100">
                              {anchor.eventType} · {anchor.side.toUpperCase()} · P{anchor.period}{" "}
                              {formatClock(anchor.clockRemainingMs)}
                              {anchor.playerName ? ` · ${anchor.playerName}` : ""}
                            </div>
                            <div className="mt-1 text-xs text-slate-500">
                              Event #{anchor.gameEventId} · {anchor.anchorSource} · offset{" "}
                              {formatDuration(anchor.recordingOffsetMs)} · suggested clip{" "}
                              {formatDuration(anchor.suggestedClipWindow.durationMs)}
                            </div>
                            {anchor.voidedAt && (
                              <div className="mt-2 text-sm text-rose-300">
                                Voided event — excluded from highlight generation.
                              </div>
                            )}
                          </div>

                          {canManageStreaming && anchor.eligibleForHighlights && (
                            <button
                              type="button"
                              disabled={clipBusyEventId === anchor.gameEventId}
                              onClick={() => void queueClip(anchor)}
                            >
                              {clipBusyEventId === anchor.gameEventId
                                ? "Queuing…"
                                : eventJobs.length > 0
                                  ? "Ensure clip"
                                  : "Generate clip"}
                            </button>
                          )}
                        </div>

                        {eventJobs.length > 0 && (
                          <div className="mt-4 space-y-2 border-t border-slate-800 pt-3">
                            {eventJobs.map((job) => (
                              <div
                                key={job.id}
                                className="flex flex-col gap-2 rounded-lg bg-slate-900/60 p-3 sm:flex-row sm:items-center sm:justify-between"
                              >
                                <div>
                                  <div className="text-sm font-medium text-slate-200">
                                    Clip job #{job.id} · {job.status}
                                  </div>
                                  <div className="mt-1 text-xs text-slate-500">
                                    {formatDuration(job.durationMs)} · {job.selectionSource} ·
                                    attempt {job.attemptCount}
                                    {job.errorMessage ? ` · ${job.errorMessage}` : ""}
                                  </div>
                                </div>

                                {job.status === "READY" && job.outputMediaAssetId != null && (
                                  <button
                                    type="button"
                                    className="secondary"
                                    disabled={clipPlaybackBusyId === job.id}
                                    onClick={() => void openClipPlayback(job)}
                                  >
                                    {clipPlaybackBusyId === job.id ? "Opening…" : "Play clip"}
                                  </button>
                                )}
                              </div>
                            ))}
                          </div>
                        )}
                      </article>
                    );
                  })}
                </div>
              )}
            </section>
          )}

          {playbackUrl && playingRecordingId != null && (
            <section className="mt-6 rounded-xl border border-slate-800 bg-slate-950/40 p-4">
              <div className="mb-3 flex items-center justify-between gap-3">
                <h2 className="text-lg font-semibold text-slate-100">
                  Recording #{playingRecordingId}
                </h2>
                <button
                  type="button"
                  className="secondary"
                  onClick={() => {
                    setPlaybackUrl(null);
                    setPlayingRecordingId(null);
                  }}
                >
                  Close player
                </button>
              </div>

              <video
                key={playbackUrl}
                className="w-full rounded-lg bg-black"
                controls
                playsInline
                preload="metadata"
                src={playbackUrl}
              />
            </section>
          )}

          <p className="mt-6 text-xs leading-5 text-slate-500">
            Playback uses a short-lived HttpOnly media session and byte-range streaming. The normal
            SportsOS bearer token is never placed in the media URL.
          </p>
        </main>
      </AppShell>
    </AuthGate>
  );
}
