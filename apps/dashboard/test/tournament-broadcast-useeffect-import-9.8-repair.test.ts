import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 9.8 useEffect import repair", () => {
  it("imports every React hook used by the broadcast operator panel", () => {
    const component = fs.readFileSync(
      new URL(
        "../components/tournament/TournamentBroadcastOperatorPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toMatch(
      /import\s+\{[^}]*useEffect[^}]*\}\s+from\s+"react";/,
    );

    expect(component).toContain("useEffect(() =>");
  });
});
