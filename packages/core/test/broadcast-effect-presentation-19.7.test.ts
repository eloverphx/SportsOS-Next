import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.7 broadcast effect presentation", () => {
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

  it("consumes the existing scoreboard effect channel", () => {
    expect(
      overlay,
    ).toContain(
      '"scoreboard:effect"',
    );

    expect(
      overlay,
    ).toContain(
      "BroadcastEffectPayload",
    );
  });

  it("supports goal and penalty effect types", () => {
    expect(
      overlay,
    ).toContain(
      '"GOAL"',
    );

    expect(
      overlay,
    ).toContain(
      '"PENALTY"',
    );

    expect(
      overlay,
    ).toContain(
      '"PENALTY ENDED"',
    );
  });

  it("automatically clears presentation effects", () => {
    expect(
      overlay,
    ).toContain(
      "Broadcast effect auto-clear",
    );

    expect(
      overlay,
    ).toContain(
      "5000",
    );

    expect(
      overlay,
    ).toContain(
      "4000",
    );
  });

  it("renders effect metadata when available", () => {
    expect(
      overlay,
    ).toContain(
      "effect.playerName",
    );

    expect(
      overlay,
    ).toContain(
      "effect.infraction",
    );

    expect(
      overlay,
    ).toContain(
      "effect.penaltyMinutes",
    );
  });

  it("adds dedicated presentation styling", () => {
    expect(
      css,
    ).toContain(
      ".effectCard",
    );

    expect(
      css,
    ).toContain(
      ".effectGOAL",
    );

    expect(
      css,
    ).toContain(
      ".effectPENALTY",
    );
  });
});
