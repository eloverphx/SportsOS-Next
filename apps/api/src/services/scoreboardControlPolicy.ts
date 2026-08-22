import fs from "node:fs";
import path from "node:path";

import type {
  ScoreboardPhysicalControlPolicy,
  ScoreboardPhysicalControlPolicyDecision,
  ScoreboardPhysicalControlPolicyMode,
  ScoreboardPhysicalControlPolicyScope,
} from "@sportsos/core";

type Store = {
  version: 1;
  policies: ScoreboardPhysicalControlPolicy[];
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
    "scoreboard-control-policy.json",
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
        parsed.policies,
      )
    ) {
      throw new Error(
        "Invalid physical control policy store.",
      );
    }

    return parsed;
  } catch {
    return {
      version: 1,
      policies: [],
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

  const temp =
    `${STORE_FILE}.tmp`;

  fs.writeFileSync(
    temp,
    JSON.stringify(
      store,
      null,
      2,
    ),
    "utf8",
  );

  fs.renameSync(
    temp,
    STORE_FILE,
  );
}

function keyOf(
  scope: ScoreboardPhysicalControlPolicyScope,
): string {
  return [
    scope.scopeType,
    scope.gameId ?? "",
    scope.deviceId ?? "",
  ].join(":");
}

export function getScoreboardPhysicalControlPolicyByScope(
  scope: ScoreboardPhysicalControlPolicyScope,
): ScoreboardPhysicalControlPolicy | null {
  const key =
    keyOf(scope);

  return (
    store.policies.find(
      (item) =>
        keyOf(item) ===
        key,
    ) ?? null
  );
}

export function setScoreboardPhysicalControlPolicy(
  scope: ScoreboardPhysicalControlPolicyScope,
  mode: ScoreboardPhysicalControlPolicyMode,
  reason?: string | null,
): ScoreboardPhysicalControlPolicy {
  const policy:
    ScoreboardPhysicalControlPolicy = {
      ...scope,
      mode,
      reason:
        reason?.trim() || null,
      updatedAt:
        new Date().toISOString(),
    };

  const key =
    keyOf(scope);

  store.policies =
    store.policies.filter(
      (item) =>
        keyOf(item) !== key,
    );

  store.policies.push(
    policy,
  );

  persistStore();

  return policy;
}

export function deleteScoreboardPhysicalControlPolicy(
  scope: ScoreboardPhysicalControlPolicyScope,
): boolean {
  const key =
    keyOf(scope);

  const before =
    store.policies.length;

  store.policies =
    store.policies.filter(
      (item) =>
        keyOf(item) !== key,
    );

  if (
    store.policies.length !==
    before
  ) {
    persistStore();
    return true;
  }

  return false;
}

export function listScoreboardPhysicalControlPolicies():
  ScoreboardPhysicalControlPolicy[] {
  return [...store.policies]
    .sort(
      (a, b) =>
        b.updatedAt.localeCompare(
          a.updatedAt,
        ),
    );
}

export function evaluateScoreboardPhysicalControlPolicy(
  gameId: string,
  deviceId: string,
): ScoreboardPhysicalControlPolicyDecision {
  const matches =
    store.policies.filter(
      (policy) =>
        (
          policy.scopeType ===
            "GAME_DEVICE" &&
          policy.gameId ===
            gameId &&
          policy.deviceId ===
            deviceId
        ) ||
        (
          policy.scopeType ===
            "GAME" &&
          policy.gameId ===
            gameId
        ) ||
        (
          policy.scopeType ===
            "DEVICE" &&
          policy.deviceId ===
            deviceId
        ),
    );

  const priority =
    (
      policy:
        ScoreboardPhysicalControlPolicy,
    ) =>
      policy.scopeType ===
        "GAME_DEVICE"
        ? 3
        : policy.scopeType ===
            "GAME"
          ? 2
          : 1;

  matches.sort(
    (a, b) =>
      priority(b) -
      priority(a),
  );

  const matched =
    matches[0] ??
    null;

  /*
   * Default is ENABLED to preserve existing deployed behavior.
   * A server-side LOCKED policy is authoritative and cannot be bypassed by
   * dashboard localStorage or client-side test overrides.
   */
  if (!matched) {
    return {
      allowed: true,
      effectiveMode:
        "ENABLED",
      matchedPolicy:
        null,
      reason:
        null,
    };
  }

  return {
    allowed:
      matched.mode ===
      "ENABLED",
    effectiveMode:
      matched.mode,
    matchedPolicy:
      matched,
    reason:
      matched.reason,
  };
}
