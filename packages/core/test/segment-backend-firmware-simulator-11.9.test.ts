import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.9 segment backend and firmware simulator", () => {
  it("defines a concrete shift-register segment backend", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/SegmentDisplayBackend.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("shiftOut");
    expect(source).toContain("encodeDigit");
    expect(source).toContain("latchPin");
  });

  it("maps decimal digits to seven-segment bit patterns", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/SegmentDisplayBackend.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("0b00111111");
    expect(source).toContain("0b01101111");
  });

  it("keeps output pins configurable", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/SegmentDisplayBackend.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "dataPin",
      "clockPin",
      "latchPin",
      "activeHigh",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("adds a host-side firmware behavior simulator", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain("buildNumericSnapshot");
    expect(simulator).toContain("renderSevenSegment");
    expect(simulator).toContain("tickFrame");
  });

  it("adds standalone simulator tests without PlatformIO", () => {
    const packageJson = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/package.json",
        import.meta.url,
      ),
      "utf8",
    );

    expect(packageJson).toContain("node --test");
  });
});
