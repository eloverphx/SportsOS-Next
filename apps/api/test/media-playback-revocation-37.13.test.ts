import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mediaRoute = readFileSync(path.resolve(__dirname, "../src/routes/media.ts"), "utf8");
const corsPlugin = readFileSync(path.resolve(__dirname, "../src/plugins/cors.ts"), "utf8");

describe("M37.13 playback revocation hardening", () => {
  it("revalidates the current database account for every playback request", () => {
    expect(mediaRoute).toContain("async function currentPlaybackIdentity");
    expect(mediaRoute).toContain("FROM users");
    expect(mediaRoute).toContain('String(account.account_status) !== "ACTIVE"');
    expect(mediaRoute).toContain("Number(account.organization_id) !== organizationId");
    expect(mediaRoute).toContain("normalizeRole(account.role)");
  });

  it("uses the ticket only to identify the subject, not as final authorization", () => {
    const routeStart = mediaRoute.indexOf('app.get("/media/playback/:id"');
    const nextRoute = mediaRoute.indexOf('app.get("/media/:id"', routeStart);
    const playbackRoute = mediaRoute.slice(routeStart, nextRoute);

    expect(playbackRoute).toContain(
      "currentPlaybackIdentity(ticket.userId, ticket.organizationId)",
    );
    expect(playbackRoute).toContain("findMediaAsset(ticket.assetId, identity.userId)");
    expect(playbackRoute).toContain("!canViewMedia(identity, asset)");
  });

  it("continues to hide authorization failures as media-not-found responses", () => {
    const routeStart = mediaRoute.indexOf('app.get("/media/playback/:id"');
    const nextRoute = mediaRoute.indexOf('app.get("/media/:id"', routeStart);
    const playbackRoute = mediaRoute.slice(routeStart, nextRoute);

    expect(playbackRoute).not.toContain("403");
    expect(playbackRoute).toContain('error: "Media not found"');
  });

  it("keeps credentialed CORS restricted to the configured dashboard origin", () => {
    expect(corsPlugin).toContain("origin: config.dashboard.origin");
    expect(corsPlugin).toContain("credentials: true");
    expect(corsPlugin).not.toContain('origin: "*"');
  });

  it("retains HttpOnly scoped playback cookies and range streaming", () => {
    expect(mediaRoute).toContain('"HttpOnly"');
    expect(mediaRoute).toContain('"SameSite=Lax"');
    expect(mediaRoute).toContain("playbackCookiePath(assetId)");
    expect(mediaRoute).toContain("minio.getPartialObject");
    expect(mediaRoute).toContain("reply.code(206)");
    expect(mediaRoute).toContain("reply.code(416)");
  });
});
