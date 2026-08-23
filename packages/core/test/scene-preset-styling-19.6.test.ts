import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.6 scene preset styling", () => {
  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const css =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/overlay.module.css",
        import.meta.url,
      ),
      "utf8",
    );

  it("applies minimal presentation behavior", () => {
    expect(overlay).toContain(
      'scenePreset !== "MINIMAL"',
    );

    expect(css).toContain(
      '[data-scene-preset="MINIMAL"]',
    );
  });

  it("applies sponsor-focus presentation behavior", () => {
    expect(overlay).toContain(
      'scenePreset === "SPONSOR_FOCUS"',
    );

    expect(overlay).toContain(
      "styles.sponsorFocus",
    );

    expect(css).toContain(
      ".sponsorFocus",
    );
  });

  it("keeps authoritative game-state fields in the overlay", () => {
    expect(overlay).toContain(
      "game.homeScore",
    );

    expect(overlay).toContain(
      "game.awayScore",
    );

    expect(overlay).toContain(
      "game.clockRemainingMs",
    );
  });
});
