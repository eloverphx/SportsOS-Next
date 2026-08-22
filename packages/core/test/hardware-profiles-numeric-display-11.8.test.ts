import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.8 hardware profiles and numeric display", () => {
  it("defines named scoreboard hardware profiles", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardHardwareProfile.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "minimal-bench",
    );
    expect(source).toContain(
      "standard-hockey",
    );
  });

  it("defines configurable numeric display geometry", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardHardwareProfile.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "homeScoreDigits",
      "awayScoreDigits",
      "periodDigits",
      "clockMinuteDigits",
      "clockSecondDigits",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("converts milliseconds into clock minutes and seconds", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/NumericScoreboardDisplayDriver.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "totalSeconds / 60UL",
    );
    expect(source).toContain(
      "totalSeconds % 60UL",
    );
  });

  it("keeps numeric rendering backend-extensible", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/NumericScoreboardDisplayDriver.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "virtual void writeNumericSnapshot",
    );
    expect(header).toContain(
      "virtual void writeHornOutput",
    );
    expect(header).toContain(
      "virtual void writeHealthOutput",
    );
  });

  it("avoids high-current or mains-power hardware assumptions", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "No high-current display wiring or mains-power switching is defined here.",
    );
  });
});
