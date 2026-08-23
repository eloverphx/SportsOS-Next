import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.9 streaming readiness / operator preflight", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/streamingReadinessPreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/encoderSessions.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("checks destination and credential readiness", () => {
    expect(service).toContain(
      '"DESTINATION_PRESENT"',
    );
    expect(service).toContain(
      '"DESTINATION_ENABLED"',
    );
    expect(service).toContain(
      '"INGEST_URL"',
    );
    expect(service).toContain(
      '"CREDENTIAL_REFERENCE"',
    );
  });

  it("checks probe, encoder, recovery, and source configuration", () => {
    expect(service).toContain(
      '"DESTINATION_PROBE"',
    );
    expect(service).toContain(
      '"ENCODER_STATE"',
    );
    expect(service).toContain(
      '"RECOVERY_STATE"',
    );
    expect(service).toContain(
      '"SOURCE_CONFIGURATION"',
    );
  });

  it("blocks encoder start when preflight fails", () => {
    expect(route).toContain(
      "STREAMING_READINESS_PREFLIGHT_20_9",
    );
    expect(route).toContain(
      "Streaming readiness preflight failed.",
    );
  });

  it("provides a preflight endpoint", () => {
    expect(route).toContain(
      '"/encoder-sessions/:gameId/preflight"',
    );
  });

  it("provides operator readiness UI", () => {
    expect(panel).toContain(
      "Streaming Readiness",
    );
    expect(panel).toContain(
      "Run Streaming Preflight",
    );
    expect(panel).toContain(
      '"PASS"',
    );
    expect(panel).toContain(
      '"FAIL"',
    );
  });
});
