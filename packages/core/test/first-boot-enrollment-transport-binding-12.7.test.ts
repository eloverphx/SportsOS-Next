import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.7 first-boot enrollment transport", () => {
  it("defines an enrollment HTTP client", () => {
    const header = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/include/EnrollmentClient.h",
        import.meta.url,
      ),
      "utf8",
    );

    expect(header).toContain(
      "EnrollmentClient",
    );

    expect(header).toContain(
      "EnrollmentClientState",
    );
  });

  it("posts first-boot identity to the SportsOS API", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/EnrollmentClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "/scoreboard-devices/enrollment/first-boot",
    );

    expect(source).toContain(
      "http.POST",
    );

    expect(source).toContain(
      "buildFirstBootJson",
    );
  });

  it("polls enrollment status until verified or rejected", () => {
    const source = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/EnrollmentClient.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      '"VERIFIED"',
    );

    expect(source).toContain(
      '"REJECTED"',
    );

    expect(source).toContain(
      "retryIntervalMs",
    );
  });

  it("binds enrollment client into firmware main loop", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "EnrollmentClient",
    );

    expect(main).toContain(
      "enrollmentClient->loop",
    );
  });

  it("defines a configurable local API base URL", () => {
    const main = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/src/main.cpp",
        import.meta.url,
      ),
      "utf8",
    );

    expect(main).toContain(
      "SPORTSOS_API_BASE_URL",
    );

    expect(main).toContain(
      "http://192.168.5.3:4001",
    );
  });
});
