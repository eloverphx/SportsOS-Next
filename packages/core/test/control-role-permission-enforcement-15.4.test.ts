import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.4 control role / permission enforcement", () => {
  const authz = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlAuthorization.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const inputRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines separate read and write permissions", () => {
    expect(authz).toContain('"CONTROL_POLICY_READ"');
    expect(authz).toContain('"CONTROL_POLICY_WRITE"');
  });

  it("reserves writes for elevated operator roles", () => {
    expect(authz).toContain('"TOURNAMENT_DIRECTOR"');
    expect(authz).toContain('"ORGANIZATION_ADMIN"');
    expect(authz).toContain("WRITE_ROLES");
  });

  it("enforces permission checks on policy routes", () => {
    expect(policyRoute).toContain("hasScoreboardControlPermission");
    expect(policyRoute).toContain('"CONTROL_POLICY_READ"');
    expect(policyRoute).toContain('"CONTROL_POLICY_WRITE"');
    expect(policyRoute).toContain("reply.code(403)");
  });

  it("keeps device-originated control authorization separate", () => {
    expect(inputRoute).toContain("DEVICE_ORIGINATED_CONTROL_AUTHORIZATION");
    expect(inputRoute).toContain("isVerifiedDevice");
  });

  it("does not trust role headers directly", () => {
    expect(authz).not.toContain("request.headers");
    expect(authz).not.toContain("x-sportsos-role");
  });
});
