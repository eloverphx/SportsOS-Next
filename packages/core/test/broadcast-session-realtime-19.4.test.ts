import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.4 realtime contract repair", () => {
  const route =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/routes/broadcastSessionProfiles.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const realtime =
    fs.readFileSync(
      new URL(
        "../../../packages/core/src/contracts/realtime.ts",
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

  it("uses the established realtime server accessor", () => {
    expect(route).toContain(
      'import { realtime } from "../infrastructure/realtime.js";',
    );

    expect(route).toContain(
      "realtime().to(",
    );

    expect(route).not.toContain(
      "app.io",
    );
  });

  it("targets the actual public game room", () => {
    expect(route).toContain(
      "`game:${gameId}`",
    );

    expect(route).not.toContain(
      "`public-game:${gameId}`",
    );
  });

  it("registers broadcast-session events in the shared realtime contract", () => {
    expect(realtime).toContain(
      "BroadcastSessionUpdatedPayload",
    );

    expect(realtime).toContain(
      '"broadcast-session:updated"',
    );

    expect(realtime).toContain(
      '"broadcast-session:deleted"',
    );
  });

  it("keeps overlay listeners strongly typed", () => {
    expect(overlay).toContain(
      '"broadcast-session:updated"',
    );

    expect(overlay).toContain(
      '"broadcast-session:deleted"',
    );
  });
});
