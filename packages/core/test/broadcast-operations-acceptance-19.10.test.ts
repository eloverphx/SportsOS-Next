import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.10 broadcast operations acceptance", () => {
  const acceptance =
    fs.readFileSync(
      new URL(
        "../../../docs/BROADCAST-OPERATIONS-ACCEPTANCE.md",
        import.meta.url,
      ),
      "utf8",
    );

  const profile =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("documents presentation-only authority boundary", () => {
    expect(
      acceptance,
    ).toContain(
      "presentation-only",
    );

    expect(
      acceptance,
    ).toContain(
      "Authoritative game state",
    );
  });

  it("retains persisted broadcast-session configuration", () => {
    expect(
      profile,
    ).toContain(
      "BroadcastSessionProfile",
    );

    expect(
      profile,
    ).toContain(
      "scenePreset",
    );

    expect(
      profile,
    ).toContain(
      "soundEnabled",
    );
  });

  it("retains realtime presentation updates", () => {
    expect(
      overlay,
    ).toContain(
      '"broadcast-session:updated"',
    );

    expect(
      overlay,
    ).toContain(
      '"scoreboard:effect"',
    );

    expect(
      overlay,
    ).toContain(
      '"scoreboard:sound"',
    );
  });

  it("retains sponsor rotation and scene presets", () => {
    expect(
      overlay,
    ).toContain(
      "Sponsor rotation timer",
    );

    expect(
      overlay,
    ).toContain(
      "data-scene-preset",
    );
  });

  it("retains operator preview and audio readiness", () => {
    expect(
      panel,
    ).toContain(
      "Open Live Overlay Preview",
    );

    expect(
      panel,
    ).toContain(
      "Audio Readiness",
    );

    expect(
      panel,
    ).toContain(
      "Test Goal Audio",
    );
  });

  it("documents final validation gates", () => {
    expect(
      acceptance,
    ).toContain(
      "npm run typecheck && npm test",
    );

    expect(
      acceptance,
    ).toContain(
      "npm run test:e2e:docker",
    );
  });
});
