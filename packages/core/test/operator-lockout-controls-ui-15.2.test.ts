import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.2 operator lockout controls UI", () => {
  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  const page = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("supports game device and combined policy scopes", () => {
    for (const scope of [
      "GAME",
      "DEVICE",
      "GAME_DEVICE",
    ]) {
      expect(panel).toContain(`"${scope}"`);
    }
  });

  it("supports enabled and locked operator modes", () => {
    expect(panel).toContain('"LOCKED"');
    expect(panel).toContain('"ENABLED"');
  });

  it("uses the server policy API for reads and writes", () => {
    expect(panel).toContain(
      "/scoreboard-control-policies",
    );
    expect(panel).toContain('method: "PUT"');
    expect(panel).toContain('method: "DELETE"');
  });

  it("does not use localStorage for authority", () => {
    expect(panel).not.toContain("localStorage");
  });

  it("shows active policies and removal controls", () => {
    expect(panel).toContain("Active Policies");
    expect(panel).toContain("Remove");
  });

  it("renders on scoreboard operations page", () => {
    expect(page).toContain(
      "PhysicalControlPolicyPanel",
    );
    expect(page).toContain(
      "<PhysicalControlPolicyPanel />",
    );
  });
});
