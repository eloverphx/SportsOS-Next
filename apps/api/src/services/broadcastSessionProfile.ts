import fs from "node:fs";
import path from "node:path";

export type BroadcastScenePreset =
  | "STANDARD"
  | "MINIMAL"
  | "SPONSOR_FOCUS";

export type BroadcastSessionProfile = {
  gameId: string;
  enabled: boolean;
  title: string | null;
  sponsorUrl: string | null;
  showPowerPlay: boolean;
  showTeamLogos: boolean;
  scenePreset: BroadcastScenePreset;
  sponsorUrls: string[];
  sponsorRotationSeconds: number;
  soundEnabled: boolean;
  goalSoundUrl: string | null;
  penaltySoundUrl: string | null;
  hornSoundUrl: string | null;
  intermissionSoundUrl: string | null;
  updatedAt: string;
};

type Store = {
  version: 1;
  profiles:
    BroadcastSessionProfile[];
};

const DATA_DIR =
  process.env.SPORTSOS_DATA_DIR ??
  path.resolve(
    process.cwd(),
    "data",
  );

const STORE_FILE =
  path.join(
    DATA_DIR,
    "broadcast-session-profiles.json",
  );

let store =
  loadStore();

function loadStore(): Store {
  try {
    const parsed =
      JSON.parse(
        fs.readFileSync(
          STORE_FILE,
          "utf8",
        ),
      ) as Store;

    if (
      parsed.version !== 1 ||
      !Array.isArray(
        parsed.profiles,
      )
    ) {
      throw new Error(
        "Invalid broadcast session profile store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      profiles: [],
    };
  }
}

function persistStore(): void {
  fs.mkdirSync(
    DATA_DIR,
    {
      recursive: true,
    },
  );

  const temporary =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temporary,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temporary,
    STORE_FILE,
  );
}

export function getBroadcastSessionProfile(
  gameId: string,
): BroadcastSessionProfile | null {
  const profile =
    store.profiles.find(
      (item) =>
        item.gameId ===
        gameId,
    );

  return profile
    ? { ...profile }
    : null;
}

function normalizeOptionalUrl(
  value: string | null | undefined,
  fallback: string | null,
): string | null {
  if (value === undefined) {
    return fallback;
  }

  if (value === null) {
    return null;
  }

  return value.trim() || null;
}

export function upsertBroadcastSessionProfile(input: {
  gameId: string;
  enabled?: boolean;
  title?: string | null;
  sponsorUrl?: string | null;
  showPowerPlay?: boolean;
  showTeamLogos?: boolean;
  scenePreset?: BroadcastScenePreset;
  sponsorUrls?: string[];
  sponsorRotationSeconds?: number;
  soundEnabled?: boolean;
  goalSoundUrl?: string | null;
  penaltySoundUrl?: string | null;
  hornSoundUrl?: string | null;
  intermissionSoundUrl?: string | null;
}): BroadcastSessionProfile {
  const existing =
    getBroadcastSessionProfile(
      input.gameId,
    );

  const title =
    typeof input.title ===
      "string"
      ? input.title.trim() ||
        null
      : input.title === null
        ? null
        : existing?.title ??
          null;

  const sponsorUrl =
    typeof input.sponsorUrl ===
      "string"
      ? input.sponsorUrl.trim() ||
        null
      : input.sponsorUrl ===
          null
        ? null
        : existing?.sponsorUrl ??
          null;

  const normalizedSponsorUrls =
    Array.isArray(
      input.sponsorUrls,
    )
      ? input.sponsorUrls
          .map(
            (item) =>
              item.trim(),
          )
          .filter(Boolean)
      : existing?.sponsorUrls ??
        [];

  const rotationSeconds =
    Number.isFinite(
      input.sponsorRotationSeconds,
    ) &&
    Number(
      input.sponsorRotationSeconds,
    ) >= 3
      ? Math.floor(
          Number(
            input.sponsorRotationSeconds,
          ),
        )
      : existing?.sponsorRotationSeconds ??
        10;

  const profile:
    BroadcastSessionProfile = {
      gameId:
        input.gameId,
      enabled:
        input.enabled ??
        existing?.enabled ??
        true,
      title,
      sponsorUrl,
      showPowerPlay:
        input.showPowerPlay ??
        existing?.showPowerPlay ??
        true,
      showTeamLogos:
        input.showTeamLogos ??
        existing?.showTeamLogos ??
        true,
      scenePreset:
        input.scenePreset ??
        existing?.scenePreset ??
        "STANDARD",
      sponsorUrls:
        normalizedSponsorUrls,
      sponsorRotationSeconds:
        rotationSeconds,
      soundEnabled:
        input.soundEnabled ??
        existing?.soundEnabled ??
        false,
      goalSoundUrl:
        normalizeOptionalUrl(
          input.goalSoundUrl,
          existing?.goalSoundUrl ??
            null,
        ),
      penaltySoundUrl:
        normalizeOptionalUrl(
          input.penaltySoundUrl,
          existing?.penaltySoundUrl ??
            null,
        ),
      hornSoundUrl:
        normalizeOptionalUrl(
          input.hornSoundUrl,
          existing?.hornSoundUrl ??
            null,
        ),
      intermissionSoundUrl:
        normalizeOptionalUrl(
          input.intermissionSoundUrl,
          existing?.intermissionSoundUrl ??
            null,
        ),
      updatedAt:
        new Date().toISOString(),
    };

  store.profiles =
    store.profiles.filter(
      (item) =>
        item.gameId !==
        input.gameId,
    );

  store.profiles.push(
    profile,
  );

  persistStore();

  return {
    ...profile,
  };
}

export function deleteBroadcastSessionProfile(
  gameId: string,
): boolean {
  const before =
    store.profiles.length;

  store.profiles =
    store.profiles.filter(
      (item) =>
        item.gameId !==
        gameId,
    );

  const changed =
    store.profiles.length !==
    before;

  if (changed) {
    persistStore();
  }

  return changed;
}
