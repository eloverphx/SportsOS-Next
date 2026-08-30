import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 28.7 container recovery / restart-loop detection", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/container-recovery-check.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("tracks restart counts",()=> {
    expect(script).toContain(
      ".RestartCount",
    );

    expect(script).toContain(
      "restart-counts.env",
    );
  });

  it("detects restart loops by delta",()=> {
    expect(script).toContain(
      "SPORTSOS_RESTART_LOOP_THRESHOLD",
    );

    expect(script).toContain(
      "restart loop suspected",
    );
  });

  it("checks container status and health",()=> {
    expect(script).toContain(
      ".State.Status",
    );

    expect(script).toContain(
      ".State.Health.Status",
    );
  });

  it("is non-destructive by default",()=> {
    expect(script).toContain(
      'APPLY_RECOVERY="${SPORTSOS_APPLY_RECOVERY:-0}"',
    );

    expect(script).toContain(
      'if [[ "$APPLY_RECOVERY" == "1" ]]',
    );
  });

  it("only performs a controlled service restart",()=> {
    expect(script).toContain(
      'docker compose restart "$service"',
    );

    expect(script).not.toContain(
      "docker compose down",
    );
  });
});
