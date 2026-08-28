import fs from "node:fs";
import { describe, expect, it } from "vitest";

describe(
  "Milestone 29.7.3 operations runner failure propagation",
  () => {
    const runner = fs.readFileSync(
      "scripts/run-production-operations.sh",
      "utf8",
    );

    it("returns the child command failure from run_step", () => {
      expect(runner).toContain('if "$@"; then');
      expect(runner).toContain("local rc=$?");
      expect(runner).toContain('return "$rc"');
      expect(runner).toContain(
        'echo "FAIL $label (exit=$rc)"',
      );
    });

    it("does not unconditionally print PASS after a child command", () => {
      const match = runner.match(
        /run_step\(\)\s*\{([\s\S]*?)^\}/m,
      );

      expect(match).not.toBeNull();

      const body = match?.[1] ?? "";

      expect(body).toContain('if "$@"; then');
      expect(body).toContain('echo "PASS $label"');
      expect(body).toContain("else");
    });

    it("fails fast from run_step calls", () => {
      const outsideFunction = runner.replace(
        /run_step\(\)\s*\{[\s\S]*?^\}/m,
        "",
      );

      const calls =
        outsideFunction
          .split("\n")
          .filter((line) =>
            /^\s*run_step\s+/.test(line),
          );

      expect(calls.length).toBeGreaterThan(0);

      for (const call of calls) {
        expect(call).toMatch(/\|\|\s*exit\s+\$\?/);
      }
    });

    it("preserves pipeline exit-code capture for operation history", () => {
      expect(runner).toContain("PIPESTATUS[0]");
    });

    it("retains required production modes", () => {
      for (const mode of [
        "health)",
        "alert)",
        "recovery)",
        "mysql-backup)",
        "persistent-backup)",
        "daily)",
        "weekly)",
      ]) {
        expect(runner).toContain(mode);
      }
    });
  },
);
