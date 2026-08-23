import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.2 overlay profile consumption", () => {
  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("loads persisted broadcast profile", () => {
    expect(overlay).toContain(
      "loadBroadcastProfile",
    );

    expect(overlay).toContain(
      "/broadcast-session",
    );
  });

  it("uses saved branding", () => {
    expect(overlay).toContain(
      "profile?.title",
    );

    expect(overlay).toContain(
      "profile?.sponsorUrl",
    );
  });

  it("uses saved visibility options", () => {
    expect(overlay).toContain(
      "profile?.showPowerPlay",
    );

    expect(overlay).toContain(
      "profile?.showTeamLogos",
    );
  });

  it("retains temporary query overrides", () => {
    expect(overlay).toContain(
      'search.get("title")',
    );

    expect(overlay).toContain(
      'search.get("showPowerPlay")',
    );

    expect(overlay).toContain(
      'search.get("showTeamLogos")',
    );
  });

  it("keeps game state on public scoreboard source", () => {
    expect(overlay).toContain(
      "/scoreboard",
    );

    expect(overlay).toContain(
      "PublicScoreboardGame",
    );
  });
});
