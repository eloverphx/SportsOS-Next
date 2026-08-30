import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 20.2 stream destination operator UI / validation", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/StreamDestinationPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("supports RTMP and SRT configuration", () => {
    expect(panel).toContain(
      "RTMP / RTMPS",
    );

    expect(panel).toContain(
      "SRT",
    );
  });

  it("validates protocol-specific ingest URLs", () => {
    expect(panel).toContain(
      "rtmps?:",
    );

    expect(panel).toContain(
      "srt:",
    );

    expect(panel).toContain(
      "validateDestination",
    );
  });

  it("requires a credential reference when enabled", () => {
    expect(panel).toContain(
      "A credential reference is required",
    );

    expect(panel).toContain(
      "Do not paste a raw stream key here.",
    );
  });

  it("provides save and reset actions", () => {
    expect(panel).toContain(
      "Save Stream Destination",
    );

    expect(panel).toContain(
      "Reset Stream Destination",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "StreamDestinationPanel",
    );

    expect(page).toContain(
      "<StreamDestinationPanel />",
    );
  });
});
