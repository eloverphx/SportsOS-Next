import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 14.10 physical control acceptance / closeout", () => {
  it("adds a complete physical-control acceptance runner", () => {
    const script = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/run-physical-control-acceptance.sh",
        import.meta.url,
      ),
      "utf8",
    );

    for (const command of [
      "npm run build --workspace @sportsos/core",
      "npm run typecheck",
      "npm test",
      "node --test firmware/esp32-scoreboard/simulator/test/*.test.js",
      "build-in-docker.sh",
      "npm run build",
    ]) {
      expect(script).toContain(command);
    }
  });

  it("documents GPIO transport execution reconciliation and retry acceptance", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    for (const heading of [
      "GPIO input acceptance",
      "Control transport acceptance",
      "Duplicate/idempotency acceptance",
      "Authoritative execution acceptance",
      "Realtime reconciliation acceptance",
      "Horn/output acceptance",
      "Audit/diagnostics acceptance",
      "Offline/retry acceptance",
    ]) {
      expect(checklist).toContain(
        heading,
      );
    }
  });

  it("requires server authority for game mutations", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "The ESP32 does not directly modify authoritative game state.",
    );
  });

  it("requires duplicate-safe retry", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "Offline retry reuses the original sequence number.",
    );

    expect(checklist).toContain(
      "Retries cannot create a second authoritative mutation.",
    );
  });

  it("documents final browser E2E gate", () => {
    const checklist = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/PHYSICAL-CONTROL-ACCEPTANCE-CHECKLIST.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("documents the Milestone 14 closeout runner", () => {
    const readme = fs.readFileSync(
      new URL(
        "../../../firmware/esp32-scoreboard/README.md",
        import.meta.url,
      ),
      "utf8",
    );

    expect(readme).toContain(
      "Milestone 14.10",
    );

    expect(readme).toContain(
      "run-physical-control-acceptance.sh",
    );
  });
});
