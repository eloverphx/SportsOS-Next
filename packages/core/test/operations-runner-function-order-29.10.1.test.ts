import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.10.1 runner function ordering", () => {
  const runner = fs.readFileSync(
    "scripts/run-production-operations.sh",
    "utf8",
  );

  it("defines run_step before the dispatcher", () => {
    const runStep = runner.indexOf("run_step() {");
    const dispatcher = runner.indexOf("case ");

    expect(runStep).toBeGreaterThanOrEqual(0);
    expect(dispatcher).toBeGreaterThan(runStep);
  });

  it("preserves fail-fast child exit propagation", () => {
    expect(runner).toContain('if "$@"; then');
    expect(runner).toContain("local rc=$?");
    expect(runner).toContain('return "$rc"');
    expect(runner).toContain("PIPESTATUS[0]");
  });

  it("preserves observability refresh mode", () => {
    expect(runner).toContain("observability-refresh)");
    expect(runner).toContain(
      "refresh-operations-observability.sh",
    );
  });
});
