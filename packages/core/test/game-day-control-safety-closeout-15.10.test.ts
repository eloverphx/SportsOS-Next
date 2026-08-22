import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.10 game-day control safety acceptance / closeout", () => {
  const runner = fs.readFileSync(
    new URL(
      "../../../scripts/run-game-day-control-safety-acceptance.sh",
      import.meta.url,
    ),
    "utf8",
  );

  const checklist = fs.readFileSync(
    new URL(
      "../../../docs/GAME-DAY-CONTROL-SAFETY-ACCEPTANCE.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("adds the full Milestone 15 acceptance runner", () => {
    for (const command of [
      "npm run build --workspace @sportsos/core",
      "npm run typecheck",
      "npm test",
      "npm run build",
    ]) {
      expect(runner).toContain(command);
    }
  });

  it("covers every Milestone 15 safety layer", () => {
    for (const heading of [
      "15.1 Physical-control enable / lockout policy",
      "15.2 Operator lockout controls",
      "15.3 Game lifecycle auto-lock",
      "15.4 Role / permission enforcement",
      "15.5 Policy-change audit / actor attribution",
      "15.6 Emergency physical-control kill switch",
      "15.7 Health / safety status",
      "15.8 Incident / rejection timeline",
      "15.9 Incident acknowledgement / resolution",
    ]) {
      expect(checklist).toContain(heading);
    }
  });

  it("requires server authority for safety decisions", () => {
    expect(checklist).toContain(
      "Server owns physical-control policy state.",
    );

    expect(checklist).toContain(
      "Dashboard/localStorage state is not authority.",
    );
  });

  it("requires emergency lock enforcement before mutation", () => {
    expect(checklist).toContain(
      "Lock state is checked before authoritative execution.",
    );
  });

  it("documents the final browser E2E gate", () => {
    expect(checklist).toContain(
      "npm run test:e2e:docker",
    );
  });
});
