import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.4 enrollment persistence and claim security", () => {
  it("persists enrollment state to disk", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "scoreboard-enrollments.json",
    );

    expect(service).toContain(
      "persistStore",
    );

    expect(service).toContain(
      "fs.renameSync",
    );
  });

  it("hashes claim tokens and uses timing-safe comparison", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      'createHash("sha256")',
    );

    expect(service).toContain(
      "timingSafeEqual",
    );
  });

  it("prevents claim token reuse", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      "claimTokenConsumedAt",
    );

    expect(service).toContain(
      "record.claimTokenConsumedAt",
    );
  });

  it("rejects a verified device identity when chip ID changes", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(service).toContain(
      'existing.chipId !== input.chipId',
    );

    expect(service).toContain(
      '"REJECTED"',
    );
  });

  it("adds claim token and verified-status routes", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/claim-token",
    );

    expect(routes).toContain(
      "/verified",
    );

    expect(routes).toContain(
      "claimToken is required.",
    );
  });

  it("extends firmware enrollment contract with claim verification JSON", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/DeviceEnrollment.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "buildClaimVerificationJson",
    );
  });
});
