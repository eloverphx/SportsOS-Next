import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10 runtime duplicate scoreboard route repair", () => {
  it("keeps the canonical base scoreboard route outside the custom gateway route file", () => {
    const custom = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(custom).not.toContain(
      'app.get("/scoreboard-devices"',
    );

    expect(custom).not.toContain(
      '"/scoreboard-devices/:deviceId",\n    async',
    );
  });

  it("preserves Milestone 10 gateway endpoints", () => {
    const custom = fs.readFileSync(
      new URL(
        "../src/routes/scoreboardDevices.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/commands"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/sync-game"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/assignments"',
    );
    expect(custom).toContain(
      '"/scoreboard-devices/:deviceId/reconcile"',
    );
  });

  it("retains the existing canonical scoreboard route module", () => {
    const canonical = fs.readFileSync(
      new URL(
        "../src/modules/scoreboard-devices/routes.ts",
        import.meta.url,
      ),
      "utf8",
    );

    expect(canonical).toContain(
      "/scoreboard-devices",
    );
  });
});
