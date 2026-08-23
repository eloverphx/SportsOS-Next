import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.9 audio test controls / broadcast readiness", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides direct operator audio testing", () => {
    expect(panel).toContain(
      "function testAudioUrl",
    );

    expect(panel).toContain(
      "new Audio(",
    );

    expect(panel).toContain(
      "audio.play().catch",
    );
  });

  it("provides test controls for every supported sound", () => {
    for (const label of [
      "Test Goal Audio",
      "Test Penalty Audio",
      "Test Horn Audio",
      "Test Intermission Audio",
    ]) {
      expect(panel).toContain(
        label,
      );
    }
  });

  it("calculates audio readiness without generating game events", () => {
    expect(panel).toContain(
      "const audioReadiness",
    );

    expect(panel).toContain(
      '"Audio disabled"',
    );

    expect(panel).toContain(
      '"Audio not ready"',
    );

    expect(panel).toContain(
      '"Audio ready"',
    );

    expect(panel).not.toContain(
      'socket.emit("scoreboard:sound"',
    );
  });
});
