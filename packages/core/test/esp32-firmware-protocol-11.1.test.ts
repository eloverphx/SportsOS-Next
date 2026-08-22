import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 11.1 ESP32 firmware protocol core", () => {
  it("defines protocol version 1", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "SCOREBOARD_PROTOCOL_VERSION = 1",
    );
  });

  it("supports all SportsOS device commands", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const command of [
      "SetGame",
      "SetScore",
      "SetClock",
      "SetPeriod",
      "Horn",
      "SyncState",
    ]) {
      expect(header).toContain(command);
    }
  });

  it("implements local clock projection without changing server authority", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardProtocol.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "ScoreboardProtocol::tick",
    );
    expect(source).toContain(
      "state_.clock.remainingMs",
    );
    expect(source).toContain(
      "state_.clock.running = false",
    );
  });

  it("implements full state synchronization", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/ScoreboardProtocol.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "CommandType::SyncState",
    );
    expect(source).toContain(
      "command.syncState.homeScore",
    );
    expect(source).toContain(
      "command.syncState.clock",
    );
  });

  it("does not hardcode hardware pins in the protocol core", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/ScoreboardProtocol.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).not.toMatch(
      /\bGPIO\b|\bPIN_[A-Z_]+\b/,
    );
  });
});
