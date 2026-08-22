import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type EnrollmentStatus =
  | "UNENROLLED"
  | "PENDING"
  | "VERIFIED"
  | "REJECTED"
  | "RETIRED";

export type ScoreboardEnrollmentRecord = {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
  status: EnrollmentStatus;
  firstSeenAt: string;
  lastSeenAt: string;
  verifiedAt: string | null;
  claimTokenHash: string | null;
  claimTokenIssuedAt: string | null;
  claimTokenConsumedAt: string | null;
  retiredAt: string | null;
};

type EnrollmentStore = {
  version: 1;
  devices: Record<
    string,
    ScoreboardEnrollmentRecord
  >;
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
    "scoreboard-enrollments.json",
  );

let store: EnrollmentStore =
  loadStore();

function loadStore(): EnrollmentStore {
  try {
    const raw =
      fs.readFileSync(
        STORE_FILE,
        "utf8",
      );

    const parsed =
      JSON.parse(raw) as EnrollmentStore;

    if (
      parsed?.version !== 1 ||
      typeof parsed.devices !==
        "object"
    ) {
      throw new Error(
        "Invalid enrollment store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      devices: {},
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

  const tempFile =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    tempFile,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    tempFile,
    STORE_FILE,
  );
}

function hashClaimToken(
  token: string,
): string {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

export function issueClaimToken(
  deviceId: string,
): string | null {
  const record =
    store.devices[deviceId];

  if (!record) {
    return null;
  }

  const token =
    crypto
      .randomBytes(24)
      .toString("hex");

  record.claimTokenHash =
    hashClaimToken(token);

  record.claimTokenIssuedAt =
    new Date().toISOString();

  record.claimTokenConsumedAt =
    null;

  persistStore();

  return token;
}

export function registerFirstBoot(input: {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
}): ScoreboardEnrollmentRecord {
  const now =
    new Date().toISOString();

  const existing =
    store.devices[input.deviceId];

  if (existing) {
    if (
      existing.chipId !== input.chipId &&
      existing.status === "VERIFIED"
    ) {
      const rejected = {
        ...existing,
        status:
          "REJECTED" as const,
        lastSeenAt:
          now,
      };

      store.devices[
        input.deviceId
      ] = rejected;

      persistStore();

      return rejected;
    }

    const updated = {
      ...existing,
      firmwareVersion:
        input.firmwareVersion,
      chipId:
        input.chipId,
      lastSeenAt:
        now,
    };

    store.devices[
      input.deviceId
    ] = updated;

    persistStore();

    return updated;
  }

  const created: ScoreboardEnrollmentRecord = {
    deviceId:
      input.deviceId,
    firmwareVersion:
      input.firmwareVersion,
    chipId:
      input.chipId,
    status:
      "PENDING",
    firstSeenAt:
      now,
    lastSeenAt:
      now,
    verifiedAt:
      null,
    claimTokenHash:
      null,
    claimTokenIssuedAt:
      null,
    claimTokenConsumedAt:
      null,
    retiredAt:
      null,
  };

  store.devices[
    input.deviceId
  ] = created;

  persistStore();

  return created;
}

export function verifyEnrollmentWithClaim(
  deviceId: string,
  claimToken: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    !record.claimTokenHash ||
    record.claimTokenConsumedAt
  ) {
    return null;
  }

  const receivedHash =
    hashClaimToken(
      claimToken,
    );

  const expected =
    Buffer.from(
      record.claimTokenHash,
      "hex",
    );

  const received =
    Buffer.from(
      receivedHash,
      "hex",
    );

  if (
    expected.length !==
      received.length ||
    !crypto.timingSafeEqual(
      expected,
      received,
    )
  ) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "VERIFIED" as const,
    verifiedAt:
      now,
    lastSeenAt:
      now,
    claimTokenConsumedAt:
      now,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function rejectEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (!record) {
    return null;
  }

  const updated = {
    ...record,
    status:
      "REJECTED" as const,
    lastSeenAt:
      new Date().toISOString(),
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function getEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  return (
    store.devices[
      deviceId
    ] ?? null
  );
}

export function listEnrollments():
  ScoreboardEnrollmentRecord[] {
  return Object
    .values(
      store.devices,
    )
    .sort(
      (a, b) =>
        b.lastSeenAt.localeCompare(
          a.lastSeenAt,
        ),
    );
}

export function isVerifiedDevice(
  deviceId: string,
  chipId?: string,
): boolean {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    record.status !==
      "VERIFIED"
  ) {
    return false;
  }

  if (
    chipId &&
    record.chipId !== chipId
  ) {
    return false;
  }

  return true;
}


export function retireEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (!record) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "RETIRED" as const,
    retiredAt:
      now,
    lastSeenAt:
      now,
    claimTokenHash:
      null,
    claimTokenConsumedAt:
      record.claimTokenConsumedAt ??
      now,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}

export function reactivateEnrollment(
  deviceId: string,
): ScoreboardEnrollmentRecord | null {
  const record =
    store.devices[deviceId];

  if (
    !record ||
    record.status !==
      "RETIRED"
  ) {
    return null;
  }

  const now =
    new Date().toISOString();

  const updated = {
    ...record,
    status:
      "PENDING" as const,
    verifiedAt:
      null,
    retiredAt:
      null,
    lastSeenAt:
      now,
    claimTokenHash:
      null,
    claimTokenIssuedAt:
      null,
    claimTokenConsumedAt:
      null,
  };

  store.devices[
    deviceId
  ] = updated;

  persistStore();

  return updated;
}
