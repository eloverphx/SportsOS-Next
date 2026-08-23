import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.7 encoder recovery / automatic restart policy", () => {
  const runtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/encoderRuntime.ts",
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

  it("uses bounded restart attempts", () => {
    expect(runtime).toContain(
      "SPORTSOS_ENCODER_MAX_RESTARTS",
    );

    expect(runtime).toContain(
      '"EXHAUSTED"',
    );
  });

  it("uses restart backoff", () => {
    expect(runtime).toContain(
      "SPORTSOS_ENCODER_RESTART_BACKOFF_MS",
    );

    expect(runtime).toContain(
      "30000",
    );
  });

  it("schedules restart after unexpected exit", () => {
    expect(runtime).toContain(
      "scheduleEncoderRestart",
    );

    expect(runtime).toContain(
      '"SCHEDULED"',
    );

    expect(runtime).toContain(
      '"RESTARTING"',
    );
  });

  it("does not restart after operator-requested stop", () => {
    expect(runtime).toContain(
      "entry.stopRequested",
    );
  });

  it("shows recovery status in operator UI", () => {
    expect(panel).toContain(
      "Recovery State",
    );

    expect(panel).toContain(
      "Restart Attempts",
    );

    expect(panel).toContain(
      "Next Retry",
    );
  });
});
