import {
  encoderRuntimeSnapshot,
} from "./encoderRuntime.js";

import {
  getStreamDestinationProfile,
} from "./streamDestinationProfile.js";

export type StreamingReadinessCheck = {
  id:
    | "DESTINATION_PRESENT"
    | "DESTINATION_ENABLED"
    | "INGEST_URL"
    | "CREDENTIAL_REFERENCE"
    | "DESTINATION_PROBE"
    | "ENCODER_STATE"
    | "RECOVERY_STATE"
    | "SOURCE_CONFIGURATION";
  passed: boolean;
  message: string;
};

export type StreamingReadinessPreflight = {
  gameId: string;
  ready: boolean;
  checkedAt: string;
  checks: StreamingReadinessCheck[];
};

function sourceConfigured(): boolean {
  return Boolean(
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL
      ?.trim() ||
    process.env
      .SPORTSOS_ENCODER_SOURCE_URL_TEMPLATE
      ?.trim(),
  );
}

export function evaluateStreamingReadiness(
  gameId: string,
): StreamingReadinessPreflight {
  const destination =
    getStreamDestinationProfile(
      gameId,
    );

  const runtime =
    encoderRuntimeSnapshot(
      gameId,
    );

  const checks:
    StreamingReadinessCheck[] = [
      {
        id:
          "DESTINATION_PRESENT",
        passed:
          Boolean(
            destination,
          ),
        message:
          destination
            ? "Stream destination profile exists."
            : "Stream destination profile is missing.",
      },
      {
        id:
          "DESTINATION_ENABLED",
        passed:
          Boolean(
            destination?.enabled,
          ),
        message:
          destination?.enabled
            ? "Streaming is enabled."
            : "Streaming is disabled.",
      },
      {
        id:
          "INGEST_URL",
        passed:
          Boolean(
            destination?.ingestUrl?.trim(),
          ),
        message:
          destination?.ingestUrl
            ? "Ingest URL is configured."
            : "Ingest URL is missing.",
      },
      {
        id:
          "CREDENTIAL_REFERENCE",
        passed:
          Boolean(
            destination?.credentialRef?.trim(),
          ),
        message:
          destination?.credentialRef
            ? "Credential reference is configured."
            : "Credential reference is missing.",
      },
      {
        id:
          "DESTINATION_PROBE",
        passed:
          destination?.status ===
            "READY" ||
          destination?.status ===
            "LIVE",
        message:
          destination?.status ===
            "READY" ||
          destination?.status ===
            "LIVE"
            ? "Destination reachability is ready."
            : "Destination must pass a connection probe.",
      },
      {
        id:
          "ENCODER_STATE",
        passed:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR",
        message:
          runtime.session.status ===
            "STOPPED" ||
          runtime.session.status ===
            "ERROR"
            ? "Encoder is available to start."
            : `Encoder is currently ${runtime.session.status}.`,
      },
      {
        id:
          "RECOVERY_STATE",
        passed:
          runtime.recovery.state !==
            "EXHAUSTED",
        message:
          runtime.recovery.state !==
            "EXHAUSTED"
            ? "Encoder recovery is available."
            : "Encoder recovery attempts are exhausted.",
      },
      {
        id:
          "SOURCE_CONFIGURATION",
        passed:
          sourceConfigured(),
        message:
          sourceConfigured()
            ? "Encoder source configuration is present."
            : "Encoder source URL or source URL template is missing.",
      },
    ];

  return {
    gameId,
    ready:
      checks.every(
        (check) =>
          check.passed,
      ),
    checkedAt:
      new Date().toISOString(),
    checks,
  };
}
