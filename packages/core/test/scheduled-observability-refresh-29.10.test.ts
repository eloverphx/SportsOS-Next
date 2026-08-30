import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe("Milestone 29.10 scheduled observability refresh", () => {
  const refresh = fs.readFileSync(
    "scripts/refresh-operations-observability.sh",
    "utf8",
  );
  const runner = fs.readFileSync(
    "scripts/run-production-operations.sh",
    "utf8",
  );

  it("refreshes severity metrics before status snapshot", () => {
    const metrics = refresh.indexOf(
      'bash "$METRICS"',
    );
    const snapshot = refresh.indexOf(
      'bash "$SNAPSHOT"',
    );

    expect(metrics).toBeGreaterThan(-1);
    expect(snapshot).toBeGreaterThan(metrics);
  });

  it("accepts severity exit codes as generated states", () => {
    expect(refresh).toContain("0|2|3)");
    expect(refresh).toContain(
      "A warning/critical severity is data, not a refresh failure.",
    );
  });

  it("still fails on unexpected metrics errors", () => {
    expect(refresh).toContain(
      "severity metrics generation failed",
    );
    expect(refresh).toContain('exit "$metrics_rc"');
  });

  it("adds an explicit scheduled runner mode", () => {
    expect(runner).toContain(
      "observability-refresh)",
    );
    expect(runner).toContain(
      "refresh-operations-observability.sh",
    );
  });

  it("preserves fail-fast runner semantics", () => {
    expect(runner).toContain('if "$@"; then');
    expect(runner).toContain('return "$rc"');
    expect(runner).toContain("PIPESTATUS[0]");
  });
});
