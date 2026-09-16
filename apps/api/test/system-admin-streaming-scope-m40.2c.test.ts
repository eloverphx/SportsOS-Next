import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const recordingsRoute = readFileSync(
  new URL("../src/routes/recordings.ts", import.meta.url),
  "utf8",
);

const recordingRepository = readFileSync(
  new URL("../src/modules/recordings/repository.ts", import.meta.url),
  "utf8",
);

const recordingAccess = readFileSync(
  new URL("../src/modules/recordings/access-policy.ts", import.meta.url),
  "utf8",
);

const mediaAccess = readFileSync(
  new URL("../src/modules/media-library/access-policy.ts", import.meta.url),
  "utf8",
);

describe("M40.2c system-admin streaming organization scope", () => {
  it("lists recordings across organizations only for system admin", () => {
    expect(recordingsRoute).toContain(
      "identity.role === ROLES.SYSTEM_ADMIN ? null : identity.organizationId",
    );

    expect(recordingRepository).toContain("organizationId: number | null");

    expect(recordingRepository).toContain(
      'organizationId == null ? "" : "WHERE r.organization_id = ?"',
    );
  });

  it("allows system admin to cross recording organization boundaries", () => {
    expect(recordingAccess).toContain("identity.role === ROLES.SYSTEM_ADMIN");
  });

  it("allows system admin playback across media organization boundaries", () => {
    expect(mediaAccess).toContain("identity.role === ROLES.SYSTEM_ADMIN");
  });

  it("retains normal organization-boundary checks for other roles", () => {
    expect(recordingAccess).toContain("recording.organizationId !== identity.organizationId");

    expect(mediaAccess).toContain("if (!sameOrganization(identity, asset))");
  });
});
