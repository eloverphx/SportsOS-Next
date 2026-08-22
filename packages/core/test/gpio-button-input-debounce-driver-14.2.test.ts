import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.2 GPIO button input / debounce driver", () => {
  const header = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/include/GpioButtonInput.h",
      import.meta.url,
    ),
    "utf8",
  );

  const source = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/GpioButtonInput.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("supports configurable active level and pin mode", () => {
    expect(header).toContain(
      "ButtonActiveLevel",
    );

    expect(header).toContain(
      "ButtonPinMode",
    );

    expect(header).toContain(
      "debounceMs",
    );
  });

  it("tracks raw and stable GPIO levels for debounce", () => {
    expect(header).toContain(
      "rawLevel",
    );

    expect(header).toContain(
      "stableLevel",
    );

    expect(header).toContain(
      "lastRawChangeMs",
    );
  });

  it("waits for debounce time before changing stable state", () => {
    expect(source).toContain(
      "nowMs -",
    );

    expect(source).toContain(
      "binding.debounceMs",
    );

    expect(source).toContain(
      "state.stableLevel =",
    );
  });

  it("emits press and release edge state", () => {
    expect(header).toContain(
      "bool pressed",
    );

    expect(source).toContain(
      "emit(",
    );
  });

  it("maps physical buttons to scoreboard control intents", () => {
    for (const intent of [
      "ScoreHomeIncrement",
      "ScoreHomeDecrement",
      "ScoreAwayIncrement",
      "ScoreAwayDecrement",
      "ClockToggle",
      "PeriodIncrement",
      "HornTrigger",
    ]) {
      expect(main).toContain(
        intent,
      );
    }
  });

  it("polls the button driver from firmware loop", () => {
    expect(main).toContain(
      "scoreboardButtons.begin()",
    );

    expect(main).toContain(
      "scoreboardButtons.poll(",
    );
  });

  it("does not claim authoritative mutation in 14.2", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "does **not** yet send those events to the SportsOS API or mutate authoritative game state",
    );
  });
});
