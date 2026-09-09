import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDir = fileURLToPath(new URL(".", import.meta.url));
const apiRoot = resolve(testDir, "..");

function source(path: string): string {
  return readFileSync(resolve(apiRoot, path), "utf8");
}

const migrations = source("src/infrastructure/streaming-foundation-migrations.ts");
const mediaRoutes = source("src/routes/media.ts");
const recordingRoutes = source("src/routes/recordings.ts");
const recordingRepository = source("src/modules/recordings/repository.ts");
const app = source("src/app.ts");

describe("Milestone 37.3 media and recording ownership", () => {
  it("keeps scoreboard logo assets intentionally public", () => {
    expect(migrations).toContain("WHERE object_key LIKE 'logos/%'");
    expect(migrations).toContain("visibility = 'PUBLIC'");
    expect(mediaRoutes).toContain("VALUES (?, ?, 'IMAGE', 'PUBLIC'");
  });

  it("protects non-public object delivery with ownership and visibility policy", () => {
    expect(mediaRoutes).toContain('app.get("/media/:id"');
    expect(mediaRoutes).toContain('asset.visibility !== "PUBLIC"');
    expect(mediaRoutes).toContain("canViewMedia(identity, asset)");
    expect(mediaRoutes).toContain('"private, no-store"');
  });

  it("supports owner/admin-controlled visibility and explicit same-organization grants", () => {
    expect(mediaRoutes).toContain('"/media/assets/:id/visibility"');
    expect(mediaRoutes).toContain('"/media/assets/:id/grants/:userId"');
    expect(mediaRoutes).toContain("userBelongsToOrganization");
    expect(mediaRoutes).toContain("canManageMedia(identity, asset)");
  });

  it("binds recordings only to games and video assets in the same organization", () => {
    expect(recordingRoutes).toContain("gameBelongsToOrganization");
    expect(recordingRoutes).toContain('asset.mediaKind !== "VIDEO"');
    expect(recordingRoutes).toContain("asset.organizationId !== recording.organizationId");
    expect(recordingRepository).toContain("WHERE id = ?\n       AND organization_id = ?");
  });

  it("registers the authenticated recording API without changing the go-live coordinator", () => {
    expect(app).toContain('import { recordingRoutes } from "./routes/recordings.js";');
    expect(app).toContain("await app.register(recordingRoutes);");
    expect(recordingRoutes).toContain("PERMISSIONS.STREAM_READ");
    expect(recordingRoutes).toContain("PERMISSIONS.STREAM_MANAGE");
  });
});
