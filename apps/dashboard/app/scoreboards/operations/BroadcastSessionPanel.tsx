"use client";

import {
  useCallback,
  useEffect,
  useMemo,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  scenePreset:
    | "STANDARD"
    | "MINIMAL"
    | "SPONSOR_FOCUS";
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
};

function testAudioUrl(
  url: string,
): void {
  const normalized =
    url.trim();

  if (!normalized) {
    return;
  }

  const audio =
    new Audio(
      normalized,
    );

  audio.preload =
    "auto";

  void audio.play().catch(
    () => {
      // Browser autoplay or invalid media must not break operator controls.
    },
  );
}

export function BroadcastSessionPanel() {
  const [gameId, setGameId] = useState("");
  const [profile, setProfile] =
    useState<BroadcastSessionProfile | null>(null);
  const [title, setTitle] = useState("");
  const [sponsorUrl, setSponsorUrl] = useState("");
  const [enabled, setEnabled] = useState(true);
  const [showPowerPlay, setShowPowerPlay] = useState(true);
  const [showTeamLogos, setShowTeamLogos] = useState(true);
  const [scenePreset, setScenePreset] =
    useState<"STANDARD" | "MINIMAL" | "SPONSOR_FOCUS">("STANDARD");
  const [sponsorUrlsText, setSponsorUrlsText] = useState("");
  const [sponsorRotationSeconds, setSponsorRotationSeconds] = useState(10);
  const [soundEnabled, setSoundEnabled] = useState(false);
  const [goalSoundUrl, setGoalSoundUrl] = useState("");
  const [penaltySoundUrl, setPenaltySoundUrl] = useState("");
  const [hornSoundUrl, setHornSoundUrl] = useState("");
  const [intermissionSoundUrl, setIntermissionSoundUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadProfile =
    useCallback(async (targetGameId: string) => {
      const normalized = targetGameId.trim();

      if (!normalized) {
        setProfile(null);
        return;
      }

      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          { cache: "no-store" },
        );

      if (!response.ok) return;

      const json = await response.json();
      const nextProfile =
        json?.data?.profile ?? null;

      setProfile(nextProfile);
      setTitle(nextProfile?.title ?? "");
      setSponsorUrl(nextProfile?.sponsorUrl ?? "");
      setEnabled(nextProfile?.enabled ?? true);
      setShowPowerPlay(nextProfile?.showPowerPlay ?? true);
      setShowTeamLogos(nextProfile?.showTeamLogos ?? true);
      setScenePreset(nextProfile?.scenePreset ?? "STANDARD");
      setSponsorUrlsText(
        (nextProfile?.sponsorUrls ?? []).join("\n"),
      );
      setSponsorRotationSeconds(
        nextProfile?.sponsorRotationSeconds ?? 10,
      );
      setSoundEnabled(
        nextProfile?.soundEnabled ?? false,
      );
      setGoalSoundUrl(
        nextProfile?.goalSoundUrl ?? "",
      );
      setPenaltySoundUrl(
        nextProfile?.penaltySoundUrl ?? "",
      );
      setHornSoundUrl(
        nextProfile?.hornSoundUrl ?? "",
      );
      setIntermissionSoundUrl(
        nextProfile?.intermissionSoundUrl ?? "",
      );
    }, []);

  async function saveProfile() {
    const normalized = gameId.trim();

    if (!normalized) {
      setError(
        "Enter a game ID before saving broadcast settings.",
      );
      return;
    }

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          {
            method: "PUT",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              enabled,
              title: title.trim() || null,
              sponsorUrl: sponsorUrl.trim() || null,
              showPowerPlay,
              showTeamLogos,
            }),
          },
        );

      const json = await response.json();

      if (!response.ok) {
        throw new Error(
          json?.error ??
          `Broadcast session save failed (${response.status}).`,
        );
      }

      setProfile(json?.data?.profile ?? null);
      setError(null);
    } catch (saveError) {
      setError(
        saveError instanceof Error
          ? saveError.message
          : "Unable to save broadcast session.",
      );
    } finally {
      setBusy(false);
    }
  }

  async function resetProfile() {
    const normalized = gameId.trim();
    if (!normalized) return;

    setBusy(true);

    try {
      const response =
        await fetch(
          `${API_BASE}/broadcast-sessions/${encodeURIComponent(normalized)}`,
          { method: "DELETE" },
        );

      if (!response.ok) {
        throw new Error(
          `Broadcast session reset failed (${response.status}).`,
        );
      }

      setProfile(null);
      setTitle("");
      setSponsorUrl("");
      setEnabled(true);
      setShowPowerPlay(true);
      setShowTeamLogos(true);
      setScenePreset("STANDARD");
      setSponsorUrlsText("");
      setSponsorRotationSeconds(10);
      setSoundEnabled(false);
      setGoalSoundUrl("");
      setPenaltySoundUrl("");
      setHornSoundUrl("");
      setIntermissionSoundUrl("");
      setError(null);
    } catch (resetError) {
      setError(
        resetError instanceof Error
          ? resetError.message
          : "Unable to reset broadcast session.",
      );
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    const normalized = gameId.trim();
    if (!normalized) return;

    const timer =
      window.setTimeout(
        () => {
          void loadProfile(normalized);
        },
        350,
      );

    return () => {
      window.clearTimeout(timer);
    };
  }, [gameId, loadProfile]);

  const audioReadiness =
    useMemo(() => {
      const configured = [
        goalSoundUrl,
        penaltySoundUrl,
        hornSoundUrl,
        intermissionSoundUrl,
      ].filter(
        (url) =>
          url.trim().length > 0,
      ).length;

      if (!soundEnabled) {
        return {
          ready: true,
          label:
            "Audio disabled",
          detail:
            "Broadcast audio is intentionally muted.",
        };
      }

      if (configured === 0) {
        return {
          ready: false,
          label:
            "Audio not ready",
          detail:
            "Audio is enabled but no sound URLs are configured.",
        };
      }

      return {
        ready: true,
        label:
          "Audio ready",
        detail:
          `${configured} sound source${configured === 1 ? "" : "s"} configured.`,
      };
    }, [
      soundEnabled,
      goalSoundUrl,
      penaltySoundUrl,
      hornSoundUrl,
      intermissionSoundUrl,
    ]);

  const overlayPreviewUrl =
    useMemo(() => {
      const normalized = gameId.trim();
      if (!normalized) return null;

      return `/games/${encodeURIComponent(normalized)}/overlay`;
    }, [gameId]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h2 className="text-xl font-semibold">
            Broadcast Session
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Configure persistent overlay branding and presentation for a game.
          </p>
        </div>

        {profile && (
          <span className="rounded border border-slate-700 px-3 py-1 text-xs">
            Saved {profile.updatedAt}
          </span>
        )}
      </div>

      <div className="mt-5">
        <label className="text-xs text-slate-500">
          Game ID
        </label>
        <input
          value={gameId}
          onChange={(event) => setGameId(event.target.value)}
          placeholder="Game ID"
          className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
        />
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2">
        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Broadcast title
          </span>
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            placeholder="Organization or broadcast title"
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Sponsor image URL
          </span>
          <input
            value={sponsorUrl}
            onChange={(event) => setSponsorUrl(event.target.value)}
            placeholder="https://..."
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-3">
        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Scene preset
          </span>
          <select
            value={scenePreset}
            onChange={(event) =>
              setScenePreset(
                event.target.value as
                  | "STANDARD"
                  | "MINIMAL"
                  | "SPONSOR_FOCUS",
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          >
            <option value="STANDARD">Standard</option>
            <option value="MINIMAL">Minimal</option>
            <option value="SPONSOR_FOCUS">Sponsor Focus</option>
          </select>
        </label>

        <label className="text-sm md:col-span-2">
          <span className="text-xs text-slate-500">
            Sponsor rotation URLs
          </span>
          <textarea
            value={sponsorUrlsText}
            onChange={(event) =>
              setSponsorUrlsText(
                event.target.value,
              )
            }
            rows={3}
            placeholder={"https://...\nhttps://..."}
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>

        <label className="text-sm">
          <span className="text-xs text-slate-500">
            Rotation seconds
          </span>
          <input
            type="number"
            min={3}
            value={sponsorRotationSeconds}
            onChange={(event) =>
              setSponsorRotationSeconds(
                Number(event.target.value) || 10,
              )
            }
            className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
          />
        </label>
      </div>

      <div className="mt-5 rounded-xl border border-slate-800 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="font-semibold">
              Broadcast Audio
            </div>
            <p className="mt-1 text-xs text-slate-500">
              Optional overlay audio triggered by SportsOS scoreboard sound events.
            </p>
          </div>

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={soundEnabled}
              onChange={(event) =>
                setSoundEnabled(
                  event.target.checked,
                )
              }
            />
            Audio enabled
          </label>
        </div>

        <div className="mt-4 grid gap-4 md:grid-cols-2">
          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Goal sound URL
            </span>
            <input
              value={goalSoundUrl}
              onChange={(event) =>
                setGoalSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../goal.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Penalty sound URL
            </span>
            <input
              value={penaltySoundUrl}
              onChange={(event) =>
                setPenaltySoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../penalty.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Horn sound URL
            </span>
            <input
              value={hornSoundUrl}
              onChange={(event) =>
                setHornSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../horn.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>

          <label className="text-sm">
            <span className="text-xs text-slate-500">
              Intermission sound URL
            </span>
            <input
              value={intermissionSoundUrl}
              onChange={(event) =>
                setIntermissionSoundUrl(
                  event.target.value,
                )
              }
              placeholder="https://.../intermission.mp3"
              className="mt-1 w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2"
            />
          </label>
        </div>
      </div>

      <div className="mt-4 rounded-lg border border-slate-800 p-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="text-sm font-semibold">
              Audio Readiness
            </div>
            <div className="mt-1 text-xs text-slate-500">
              {audioReadiness.detail}
            </div>
          </div>

          <span
            className={
              `rounded border px-3 py-1 text-xs font-medium ${
                audioReadiness.ready
                  ? "border-slate-700"
                  : "border-red-900/60 text-red-300"
              }`
            }
          >
            {audioReadiness.label}
          </span>
        </div>

        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          <button
            type="button"
            disabled={!goalSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                goalSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Goal Audio
          </button>

          <button
            type="button"
            disabled={!penaltySoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                penaltySoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Penalty Audio
          </button>

          <button
            type="button"
            disabled={!hornSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                hornSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Horn Audio
          </button>

          <button
            type="button"
            disabled={!intermissionSoundUrl.trim()}
            onClick={() =>
              testAudioUrl(
                intermissionSoundUrl,
              )
            }
            className="rounded border border-slate-800 px-3 py-2 text-xs disabled:opacity-40"
          >
            Test Intermission Audio
          </button>
        </div>
      </div>


      <div className="mt-4 grid gap-3 md:grid-cols-3">
        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={enabled}
            onChange={(event) => setEnabled(event.target.checked)}
          />
          Broadcast enabled
        </label>

        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={showPowerPlay}
            onChange={(event) =>
              setShowPowerPlay(event.target.checked)
            }
          />
          Show power play
        </label>

        <label className="flex items-center gap-2 rounded-lg border border-slate-800 p-3 text-sm">
          <input
            type="checkbox"
            checked={showTeamLogos}
            onChange={(event) =>
              setShowTeamLogos(event.target.checked)
            }
          />
          Show team logos
        </label>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-900/50 bg-red-950/30 p-3 text-sm text-red-300">
          {error}
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-3">
        <button
          type="button"
          disabled={busy || !gameId.trim()}
          onClick={() => void saveProfile()}
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium disabled:opacity-50"
        >
          Save Broadcast Session
        </button>

        <button
          type="button"
          disabled={busy || !gameId.trim()}
          onClick={() => void resetProfile()}
          className="rounded-lg border border-slate-800 px-4 py-2 text-sm disabled:opacity-50"
        >
          Reset to Overlay Defaults
        </button>

        {overlayPreviewUrl && (
          <a
            href={overlayPreviewUrl}
            target="_blank"
            rel="noreferrer"
            className="rounded-lg border border-slate-700 px-4 py-2 text-sm font-medium"
          >
            Open Live Overlay Preview
          </a>
        )}
      </div>

      {overlayPreviewUrl && (
        <div className="mt-5 overflow-hidden rounded-xl border border-slate-800 bg-black">
          <div className="border-b border-slate-800 px-3 py-2 text-xs text-slate-500">
            Live Overlay Preview
          </div>
          <iframe
            title="SportsOS broadcast overlay preview"
            src={overlayPreviewUrl}
            className="aspect-video w-full border-0"
          />
        </div>
      )}
    </section>
  );
}
