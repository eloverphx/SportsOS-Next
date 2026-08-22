import {
  getEmergencyPhysicalControlLock,
} from "./scoreboardEmergencyControlLock.js";

import {
  listScoreboardPhysicalControlPolicies,
} from "./scoreboardControlPolicy.js";

export type PhysicalControlSafetyLevel =
  | "SAFE"
  | "RESTRICTED"
  | "EMERGENCY_LOCKED";

export type PhysicalControlHealthStatus = {
  level: PhysicalControlSafetyLevel;
  acceptingPhysicalControls: boolean;
  emergencyLockActive: boolean;
  activePolicyCount: number;
  lockedPolicyCount: number;
  generatedAt: string;
  summary: string;
};

export function getPhysicalControlHealthStatus():
  PhysicalControlHealthStatus {
  const emergencyLock =
    getEmergencyPhysicalControlLock();

  const policies =
    listScoreboardPhysicalControlPolicies();

  const lockedPolicies =
    policies.filter(
      (policy) =>
        policy.mode === "LOCKED",
    );

  if (emergencyLock.active) {
    return {
      level: "EMERGENCY_LOCKED",
      acceptingPhysicalControls: false,
      emergencyLockActive: true,
      activePolicyCount: policies.length,
      lockedPolicyCount: lockedPolicies.length,
      generatedAt: new Date().toISOString(),
      summary:
        emergencyLock.reason ??
        "Emergency physical-control lock is active.",
    };
  }

  if (lockedPolicies.length > 0) {
    return {
      level: "RESTRICTED",
      acceptingPhysicalControls: true,
      emergencyLockActive: false,
      activePolicyCount: policies.length,
      lockedPolicyCount: lockedPolicies.length,
      generatedAt: new Date().toISOString(),
      summary:
        `${lockedPolicies.length} physical-control policy scope(s) are locked.`,
    };
  }

  return {
    level: "SAFE",
    acceptingPhysicalControls: true,
    emergencyLockActive: false,
    activePolicyCount: policies.length,
    lockedPolicyCount: 0,
    generatedAt: new Date().toISOString(),
    summary:
      "Physical controls are globally available subject to device, assignment, lifecycle, and sequence validation.",
  };
}
