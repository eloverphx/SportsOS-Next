import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 17.10 hardware commissioning closeout", () => {
  const runner = fs.readFileSync(
    new URL("../../../scripts/run-hardware-commissioning-acceptance.sh", import.meta.url),
    "utf8",
  );

  const checklist = fs.readFileSync(
    new URL("../../../docs/HARDWARE-COMMISSIONING-ACCEPTANCE.md", import.meta.url),
    "utf8",
  );

  it("includes all acceptance gates", () => {
    for (const command of [
      "npm run typecheck",
      "npm test",
      "npm run build",
      "build-in-docker.sh",
    ]) {
      expect(runner).toContain(command);
    }
  });

  it("documents milestones 17.1 through 17.9", () => {
    for (let i = 1; i <= 9; i += 1) {
      expect(checklist).toContain(`17.${i}`);
    }
  });

  it("requires command-correlated telemetry", () => {
    expect(checklist).toContain("commandId");
    expect(checklist).toContain("COMMISSIONING_SELF_TEST");
  });

  it("keeps self-test outside authoritative game state", () => {
    expect(checklist).toContain("without modifying authoritative game state");
  });

  it("documents the final E2E gate", () => {
    expect(checklist).toContain("npm run test:e2e:docker");
  });
});
