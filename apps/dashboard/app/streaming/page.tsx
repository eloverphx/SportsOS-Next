"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API, api } from "../../lib/api";

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

interface RecordingsResponse {
  readonly recordings: Recording[];
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

  useEffect(() => {
    void loadRecordings();

    const timer = window.setInterval(() => {
      void loadRecordings(true);
    }, 30_000);

    return () => window.clearInterval(timer);
  }, [loadRecordings]);

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
                Monitor live recording capture, processing, failures, and finalized game archives.
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
                        <button
                          type="button"
                          className="secondary"
                          disabled={playbackBusyId === recording.id}
                          onClick={() => void openPlayback(recording)}
                        >
                          {playbackBusyId === recording.id ? "Opening…" : "Play recording"}
                        </button>
                      )}
                    </div>
                  </div>
                </article>
              ))
            )}
          </section>

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
