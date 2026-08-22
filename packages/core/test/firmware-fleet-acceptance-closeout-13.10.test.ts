import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 13.10 firmware fleet acceptance / closeout", () => {
  it("adds a single fleet acceptance runner", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/run-fleet-acceptance.sh",
        import.meta.url,
      ),
      "utf8",
    );

    expect(script).toContain(
      "npm run typecheck",
    );

    expect(script).toContain(
      "npm test",
    );

    expect(script).toContain(
      "node --test firmware/esp32-scoreboard/simulator/test/*.test.js",
    );

    expect(script).toContain(
      "build-in-docker.sh",
    );

    expect(script).toContain(
      "npm run build",
    );
  });

  it("documents release, rollout, OTA, and reporting acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    for (const heading of [
      "Release acceptance",
      "Device-offer acceptance",
      "OTA staging acceptance",
      "Install policy acceptance",
      "Reporting acceptance",
      "Rollout acceptance",
      "Dashboard acceptance",
    ]) {
      expect(checklist).toContain(
        heading,
      );
    }
  });

  it("requires verified devices throughout fleet management", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "Device must be VERIFIED.",
    );

    expect(checklist).toContain(
      "All targets must be VERIFIED devices.",
    );
  });

  it("requires browser E2E after fleet acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/FLEET-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("documents the Milestone 13 closeout sequence", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "Milestone 13.10",
    );

    expect(readme).toContain(
      "run-fleet-acceptance.sh",
    );
  });
});
