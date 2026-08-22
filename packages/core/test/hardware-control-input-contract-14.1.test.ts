import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
  isScoreboardControlInputType,
} from "../src/scoreboard-control-input-contract.js";

describe("Milestone 14.1 hardware control input contract", () => {
  it("defines protocol version 1", () => {
    expect(
      SCOREBOARD_CONTROL_INPUT_PROTOCOL_VERSION,
    ).toBe(1);
  });

  it("supports score clock period and horn intents", () => {
    for (const type of [
      "SCORE_HOME_INCREMENT",
      "SCORE_HOME_DECREMENT",
      "SCORE_AWAY_INCREMENT",
      "SCORE_AWAY_DECREMENT",
      "CLOCK_TOGGLE",
      "CLOCK_START",
      "CLOCK_PAUSE",
      "PERIOD_INCREMENT",
      "PERIOD_DECREMENT",
      "HORN_TRIGGER",
    ]) {
      expect(
        isScoreboardControlInputType(
          type,
        ),
      ).toBe(true);
    }
  });

  it("defines server disposition contract", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/scoreboard-control-input-contract.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      '"ACCEPTED"',
    );

    expect(source).toContain(
      '"REJECTED"',
    );

    expect(source).toContain(
      '"IGNORED_DUPLICATE"',
    );
  });

  it("defines firmware-side control input contract", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardControlInput.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "ScoreboardControlInputEvent",
    );

    expect(header).toContain(
      "sequence",
    );

    expect(header).toContain(
      "inputId",
    );
  });

  it("keeps physical control as intent rather than direct authority", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "do **not** directly mutate authoritative SportsOS game state",
    );
  });
});
