import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.5 broadcast scene presets / sponsor rotation foundation", () => {
  const service =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/broadcastSessionProfile.ts",
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

  const overlay =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/games/[id]/overlay/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("adds scene presets to broadcast profiles", () => {
    expect(service).toContain(
      '"STANDARD"',
    );
    expect(service).toContain(
      '"MINIMAL"',
    );
    expect(service).toContain(
      '"SPONSOR_FOCUS"',
    );
  });

  it("persists sponsor rotation configuration", () => {
    expect(service).toContain(
      "sponsorUrls",
    );
    expect(service).toContain(
      "sponsorRotationSeconds",
    );
  });

  it("provides operator controls", () => {
    expect(panel).toContain(
      "Scene preset",
    );
    expect(panel).toContain(
      "Sponsor rotation URLs",
    );
    expect(panel).toContain(
      "Rotation seconds",
    );
  });

  it("rotates sponsors in the overlay", () => {
    expect(overlay).toContain(
      "Sponsor rotation timer",
    );
    expect(overlay).toContain(
      "setSponsorIndex",
    );
    expect(overlay).toContain(
      "rotatingSponsorUrl",
    );
  });

  it("exposes scene preset to presentation styling", () => {
    expect(overlay).toContain(
      "data-scene-preset",
    );
  });
});
