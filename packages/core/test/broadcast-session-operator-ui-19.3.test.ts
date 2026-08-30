import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.3 broadcast session operator UI", () => {
  const panel =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/BroadcastSessionPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("loads and saves broadcast sessions", () => {
    expect(panel).toContain(
      "/broadcast-sessions/",
    );

    expect(panel).toContain(
      "Save Broadcast Session",
    );
  });

  it("provides branding and presentation controls", () => {
    expect(panel).toContain(
      "Broadcast title",
    );

    expect(panel).toContain(
      "Sponsor image URL",
    );

    expect(panel).toContain(
      "Show power play",
    );

    expect(panel).toContain(
      "Show team logos",
    );
  });

  it("provides reset behavior", () => {
    expect(panel).toContain(
      "Reset to Overlay Defaults",
    );

    expect(panel).toContain(
      'method: "DELETE"',
    );
  });

  it("provides live overlay preview", () => {
    expect(panel).toContain(
      "Open Live Overlay Preview",
    );

    expect(panel).toContain(
      "<iframe",
    );

    expect(panel).toContain(
      "/overlay",
    );
  });

  it("renders on scoreboard operations", () => {
    expect(page).toContain(
      "BroadcastSessionPanel",
    );

    expect(page).toContain(
      "<BroadcastSessionPanel />",
    );
  });
});
