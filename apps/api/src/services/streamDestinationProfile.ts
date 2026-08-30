import fs from "node:fs";
import path from "node:path";

export type StreamProtocol =
  | "RTMP"
  | "SRT";

export type StreamLatencyMode =
  | "NORMAL"
  | "LOW"
  | "ULTRA_LOW";

export type StreamDestinationStatus =
  | "DISABLED"
  | "CONFIGURED"
  | "READY"
  | "LIVE"
  | "ERROR";

export type StreamDestinationProfile = {
  gameId: string;
  enabled: boolean;
  protocol: StreamProtocol;
  ingestUrl: string | null;
  streamName: string | null;
  credentialRef: string | null;
  latencyMode: StreamLatencyMode;
  status: StreamDestinationStatus;
  lastError: string | null;
  lastProbeAt: string | null;
  lastProbeLatencyMs: number | null;
  updatedAt: string;
};

type Store = {
  version: 1;
  profiles:
    StreamDestinationProfile[];
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
    "stream-destination-profiles.json",
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
        "Invalid stream destination profile store.",
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

function optionalText(
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

export function getStreamDestinationProfile(
  gameId: string,
): StreamDestinationProfile | null {
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

export function upsertStreamDestinationProfile(input: {
  gameId: string;
  enabled?: boolean;
  protocol?: StreamProtocol;
  ingestUrl?: string | null;
  streamName?: string | null;
  credentialRef?: string | null;
  latencyMode?: StreamLatencyMode;
}): StreamDestinationProfile {
  const existing =
    getStreamDestinationProfile(
      input.gameId,
    );

  const enabled =
    input.enabled ??
    existing?.enabled ??
    false;

  const ingestUrl =
    optionalText(
      input.ingestUrl,
      existing?.ingestUrl ??
        null,
    );

  const credentialRef =
    optionalText(
      input.credentialRef,
      existing?.credentialRef ??
        null,
    );

  const configured =
    Boolean(
      ingestUrl &&
      credentialRef,
    );

  const profile:
    StreamDestinationProfile = {
      gameId:
        input.gameId,
      enabled,
      protocol:
        input.protocol ??
        existing?.protocol ??
        "RTMP",
      ingestUrl,
      streamName:
        optionalText(
          input.streamName,
          existing?.streamName ??
            null,
        ),
      credentialRef,
      latencyMode:
        input.latencyMode ??
        existing?.latencyMode ??
        "NORMAL",
      status:
        enabled
          ? configured
            ? existing?.status ===
                "LIVE"
              ? "LIVE"
              : "CONFIGURED"
            : "ERROR"
          : "DISABLED",
      lastError:
        enabled &&
        !configured
          ? "Enabled stream destination requires ingestUrl and credentialRef."
          : null,
      lastProbeAt:
        existing?.lastProbeAt ??
        null,
      lastProbeLatencyMs:
        existing?.lastProbeLatencyMs ??
        null,
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

export function updateStreamDestinationProbeResult(input: {
  gameId: string;
  reachable: boolean;
  checkedAt: string;
  latencyMs: number | null;
  error: string | null;
}): StreamDestinationProfile | null {
  const existing =
    getStreamDestinationProfile(
      input.gameId,
    );

  if (!existing) {
    return null;
  }

  const profile:
    StreamDestinationProfile = {
      ...existing,
      status:
        input.reachable
          ? "READY"
          : "ERROR",
      lastError:
        input.error,
      lastProbeAt:
        input.checkedAt,
      lastProbeLatencyMs:
        input.latencyMs,
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

export function deleteStreamDestinationProfile(
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

export function publicStreamDestinationSummary(
  gameId: string,
): {
  enabled: boolean;
  protocol: StreamProtocol | null;
  status: StreamDestinationStatus;
} {
  const profile =
    getStreamDestinationProfile(
      gameId,
    );

  if (!profile) {
    return {
      enabled: false,
      protocol: null,
      status: "DISABLED",
    };
  }

  return {
    enabled:
      profile.enabled,
    protocol:
      profile.protocol,
    status:
      profile.status,
  };
}
