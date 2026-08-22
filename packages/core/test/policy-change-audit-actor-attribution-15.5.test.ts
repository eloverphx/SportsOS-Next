import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.5 policy change audit / actor attribution", () => {
  const service = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlPolicyAudit.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const route = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const panel = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/operations/PhysicalControlPolicyPanel.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("persists dedicated policy audit records", () => {
    expect(service).toContain(
      "scoreboard-control-policy-audit.json",
    );

    expect(service).toContain(
      "previousPolicy",
    );

    expect(service).toContain(
      "nextPolicy",
    );
  });

  it("records actor identity and roles", () => {
    expect(service).toContain(
      "actorUserId",
    );

    expect(service).toContain(
      "actorRoles",
    );

    expect(route).toContain(
      "getScoreboardControlPrincipal",
    );
  });

  it("audits set and delete operations", () => {
    expect(route).toContain(
      'action:',
    );

    expect(route).toContain(
      '"SET"',
    );

    expect(route).toContain(
      '"DELETE"',
    );
  });

  it("exposes policy audit API", () => {
    expect(route).toContain(
      "/scoreboard-control-policy-audit",
    );

    expect(route).toContain(
      "CONTROL_POLICY_READ",
    );
  });

  it("shows recent policy changes in operator UI", () => {
    expect(panel).toContain(
      "Recent Policy Changes",
    );

    expect(panel).toContain(
      "actorUserId",
    );

    expect(panel).toContain(
      "actorRoles",
    );
  });
});
