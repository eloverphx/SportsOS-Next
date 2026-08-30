import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.8 broadcast sound controls / operator audio policy", () => {
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

  it("keeps broadcast audio disabled by default", () => {
    expect(service).toContain(
      "existing?.soundEnabled ??",
    );

    expect(service).toContain(
      "false",
    );
  });

  it("persists per-event sound URLs", () => {
    for (const field of [
      "goalSoundUrl",
      "penaltySoundUrl",
      "hornSoundUrl",
      "intermissionSoundUrl",
    ]) {
      expect(service).toContain(
        field,
      );
    }
  });

  it("provides operator audio controls", () => {
    expect(panel).toContain(
      "Broadcast Audio",
    );

    expect(panel).toContain(
      "Audio enabled",
    );

    expect(panel).toContain(
      "Goal sound URL",
    );

    expect(panel).toContain(
      "Horn sound URL",
    );
  });

  it("uses the existing scoreboard sound channel", () => {
    expect(overlay).toContain(
      '"scoreboard:sound"',
    );

    expect(overlay).toContain(
      "playBroadcastSound",
    );
  });

  it("does not let playback rejection break the overlay", () => {
    expect(overlay).toContain(
      "audio.play().catch",
    );

    expect(overlay).toContain(
      "Audio failure must never affect overlay rendering or game state.",
    );
  });
});
