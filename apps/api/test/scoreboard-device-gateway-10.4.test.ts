import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10.4 API scoreboard device gateway", () => {
  it("defines the MQTT-backed scoreboard gateway", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/services/scoreboardDeviceGateway.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain("class ScoreboardDeviceGateway");
    expect(source).toContain("sportsos/scoreboards/+/state");
    expect(source).toContain("sportsos/scoreboards/+/presence");
    expect(source).toContain("sportsos/scoreboards/+/telemetry");
    expect(source).toContain("sportsos/scoreboards/+/ack");
  });

  it("exposes device HTTP routes", () => {
    const route = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(route).toContain(
      '"/scoreboard-devices/:deviceId/commands"',
    );
  });

  it("registers the device routes in the discovered API file", () => {
    const source = fs.readFileSync(
      new URL(
        "../src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(source).toContain(
      "scoreboardDevicesRoutes",
    );
  });
});
