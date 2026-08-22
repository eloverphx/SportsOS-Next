import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 18.10 game-day deployment acceptance closeout", () => {
  const preflight =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameDayHardwarePreflight.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const guard =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightGuard.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const override =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/gameStartPreflightOverride.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/GameDayHardwarePreflightPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const acceptance =
    fs.readFileSync(
      new URL(
        "../../../docs/GAME-DAY-DEPLOYMENT-ACCEPTANCE.md",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains authoritative preflight and start guard services", () => {
    expect(preflight.length).toBeGreaterThan(0);
    expect(guard.length).toBeGreaterThan(0);
  });

  it("retains emergency override expiration and revocation", () => {
    expect(override).toContain(
      "expiresAt",
    );

    expect(override).toContain(
      "revokeGameStartPreflightOverride",
    );
  });

  it("retains operator countdown and auto-rerun controls", () => {
    expect(panel).toContain(
      "Start Window Guidance",
    );

    expect(panel).toContain(
      "Auto-Rerun:",
    );

    expect(panel).toContain(
      "runPreflightSilently",
    );
  });

  it("documents assignment-change invalidation", () => {
    expect(acceptance).toContain(
      "changed scoreboard assignment invalidates the prior preflight",
    );
  });

  it("documents server-authoritative start authorization", () => {
    expect(acceptance).toContain(
      "Server-side start authorization remains authoritative",
    );
  });

  it("documents controlled emergency authorization", () => {
    expect(acceptance).toContain(
      "Emergency override requires an explicit written reason",
    );

    expect(acceptance).toContain(
      "does not rewrite a failed preflight as passing",
    );
  });
});
