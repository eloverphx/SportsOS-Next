import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.4 authoritative game command binding", () => {
  const source = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlCommandBinding.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("maps home and away score controls", () => {
    expect(source).toContain(
      '"SCORE_HOME_INCREMENT"',
    );

    expect(source).toContain(
      'side: "HOME"',
    );

    expect(source).toContain(
      '"SCORE_AWAY_DECREMENT"',
    );

    expect(source).toContain(
      'side: "AWAY"',
    );
  });

  it("maps clock controls", () => {
    for (const action of [
      "CLOCK_START",
      "CLOCK_PAUSE",
      "CLOCK_TOGGLE",
    ]) {
      expect(source).toContain(
        `"${action}"`,
      );
    }

    expect(source).toContain(
      'kind: "CLOCK"',
    );
  });

  it("maps period controls", () => {
    expect(source).toContain(
      '"PERIOD_INCREMENT"',
    );

    expect(source).toContain(
      '"PERIOD_DECREMENT"',
    );

    expect(source).toContain(
      'kind: "PERIOD"',
    );
  });

  it("maps horn trigger", () => {
    expect(source).toContain(
      '"HORN_TRIGGER"',
    );

    expect(source).toContain(
      'kind: "HORN"',
    );
  });

  it("attaches command intent only after control acceptance", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardControlInputs.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      '"ACCEPTED"',
    );

    expect(service).toContain(
      "mapScoreboardControlInputToCommand",
    );
  });
});
