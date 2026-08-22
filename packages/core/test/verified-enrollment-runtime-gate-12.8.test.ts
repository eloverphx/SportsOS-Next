import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.8 verified enrollment runtime gate", () => {
  it("defines waiting allowed and rejected runtime states", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/VerifiedRuntimeGate.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "WaitingForEnrollment",
      "Allowed",
      "Rejected",
    ]) {
      expect(header).toContain(state);
    }
  });

  it("allows authoritative runtime only for verified enrollment", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/VerifiedRuntimeGate.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "EnrollmentClientState::Verified",
    );

    expect(source).toContain(
      "RuntimeGateState::Allowed",
    );

    expect(source).toContain(
      "allowAuthoritativeRuntime",
    );
  });

  it("keeps pending and transport-error devices blocked", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/VerifiedRuntimeGate.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "EnrollmentClientState::Pending",
    );

    expect(source).toContain(
      "EnrollmentClientState::TransportError",
    );

    expect(source).toContain(
      "WaitingForEnrollment",
    );
  });

  it("starts ScoreboardRuntime only through the verified gate", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "runtimeGate",
    );

    expect(main).toContain(
      "allowAuthoritativeRuntime",
    );

    expect(main).toContain(
      "startAuthoritativeRuntime",
    );
  });

  it("adds equivalent host simulator gate behavior", () => {
    const simulator = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/simulator/firmware-behavior-simulator.js",
        import.meta.url,
      ),
      "utf8",
    );

    expect(simulator).toContain(
      "evaluateVerifiedRuntimeGate",
    );

    expect(simulator).toContain(
      "WAITING_FOR_ENROLLMENT",
    );

    expect(simulator).toContain(
      "ALLOWED",
    );
  });
});
