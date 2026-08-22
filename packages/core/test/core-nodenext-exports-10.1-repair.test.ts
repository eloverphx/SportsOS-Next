import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 10.1 NodeNext export repair", () => {
  it("uses explicit .js extension for the scoreboard device contract export", () => {
    const index = fs.readFileSync(
      new URL("../src/index.ts", import.meta.url),
      "utf8",
    );

    expect(index).toContain(
      'export * from "./scoreboard-device-contract.js";',
    );
  });

  it("uses explicit .js extension for the MQTT contract export when present", () => {
    const index = fs.readFileSync(
      new URL("../src/index.ts", import.meta.url),
      "utf8",
    );

    if (index.includes("scoreboard-mqtt-contract")) {
      expect(index).toContain(
        'export * from "./scoreboard-mqtt-contract.js";',
      );
    }
  });
});
