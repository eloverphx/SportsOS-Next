import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.0 repository baseline and continuation handoff", () => {
  const resume = fs.readFileSync(
    new URL(
      "../../../docs/RESUME-HERE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const architecture = fs.readFileSync(
    new URL(
      "../../../docs/ARCHITECTURE.md",
      import.meta.url,
    ),
    "utf8",
  );

  const status = fs.readFileSync(
    new URL(
      "../../../docs/MILESTONE-STATUS.md",
      import.meta.url,
    ),
    "utf8",
  );

  it("records authoritative start path", () => {
    expect(resume).toContain(
      "POST /games/:id/lifecycle",
    );

    expect(resume).toContain(
      'command === "startGame"',
    );

    expect(resume).toContain(
      "before lifecycle mutation",
    );
  });

  it("records assignment-bound preflight", () => {
    expect(resume).toContain(
      "evaluateGameStartPreflight(",
    );

    expect(resume).toContain(
      "assignedDeviceId",
    );
  });

  it("records firmware authority boundary", () => {
    expect(architecture).toContain(
      "does not become authoritative for game state",
    );
  });

  it("records current milestone baseline", () => {
    expect(status).toContain(
      "Milestone 18.11 complete",
    );

    expect(status).toContain(
      "Milestone 19 next",
    );
  });

  it("records validation commands", () => {
    expect(resume).toContain(
      "npm run typecheck && npm test",
    );

    expect(resume).toContain(
      "build-in-docker.sh",
    );

    expect(resume).toContain(
      "npm run test:e2e:docker",
    );
  });
});
