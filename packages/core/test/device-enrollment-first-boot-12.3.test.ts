import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.3 scoreboard enrollment", () => {
  it("defines first-boot firmware identity", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/DeviceEnrollment.h",
        import.meta.url,
      ),
      "utf8",
    );

    for (const field of [
      "deviceId",
      "firmwareVersion",
      "chipId",
    ]) {
      expect(header).toContain(field);
    }
  });

  it("derives chip identity from the ESP32", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/DeviceEnrollment.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "ESP.getEfuseMac",
    );

    expect(source).toContain(
      "SPORTSOS_FIRMWARE_VERSION",
    );
  });

  it("defines server enrollment states", () => {
    const service = fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    for (const state of [
      "UNENROLLED",
      "PENDING",
      "VERIFIED",
      "REJECTED",
    ]) {
      expect(service).toContain(state);
    }
  });

  it("defines first-boot verify and reject endpoints", () => {
    const routes = fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/scoreboardDeviceEnrollment.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/first-boot",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/:deviceId/verify",
    );

    expect(routes).toContain(
      "/scoreboard-devices/enrollment/:deviceId/reject",
    );
  });

  it("adds an enrollment dashboard page", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Scoreboard Enrollment",
    );

    expect(page).toContain(
      "Verify",
    );

    expect(page).toContain(
      "Reject",
    );
  });
});
