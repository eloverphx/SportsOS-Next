export type ScoreboardPhysicalControlPolicyMode =
  | "ENABLED"
  | "LOCKED";

export type ScoreboardPhysicalControlPolicyScope =
  | {
      scopeType: "GAME";
      gameId: string;
      deviceId: null;
    }
  | {
      scopeType: "DEVICE";
      gameId: null;
      deviceId: string;
    }
  | {
      scopeType: "GAME_DEVICE";
      gameId: string;
      deviceId: string;
    };

export type ScoreboardPhysicalControlPolicy =
  ScoreboardPhysicalControlPolicyScope & {
    mode:
      ScoreboardPhysicalControlPolicyMode;
    reason:
      string | null;
    updatedAt:
      string;
  };

export type ScoreboardPhysicalControlPolicyDecision = {
  allowed: boolean;
  effectiveMode:
    ScoreboardPhysicalControlPolicyMode;
  matchedPolicy:
    ScoreboardPhysicalControlPolicy | null;
  reason:
    string | null;
};
