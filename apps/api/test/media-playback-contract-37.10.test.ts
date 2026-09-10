import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mediaRoutesFile = path.resolve(__dirname, "../src/routes/media.ts");
const dashboardFile = path.resolve(__dirname, "../../dashboard/app/streaming/page.tsx");

describe("M37.10 authenticated media playback contract", () => {
  it("issues an HttpOnly playback session after STREAM_READ authorization", () => {
    const source = readFileSync(mediaRoutesFile, "utf8");

    expect(source).toContain("permission: PERMISSIONS.STREAM_READ");
    expect(source).toContain('"/media/assets/:id/playback-session"');
    expect(source).toContain('"HttpOnly"');
    expect(source).toContain('"SameSite=Lax"');
    expect(source).not.toContain("token=");
  });

  it("serves native byte ranges from MinIO", () => {
    const source = readFileSync(mediaRoutesFile, "utf8");

    expect(source).toContain('reply.header("Accept-Ranges", "bytes")');
    expect(source).toContain("getPartialObject");
    expect(source).toContain("reply.code(206)");
    expect(source).toContain("reply.code(416)");
  });

  it("dashboard obtains the playback cookie with credentials and uses video controls", () => {
    const source = readFileSync(dashboardFile, "utf8");

    expect(source).toContain('credentials: "include"');
    expect(source).toContain("<video");
    expect(source).toContain("playsInline");
    expect(source).toContain('preload="metadata"');
    expect(source).not.toContain("sportsos_token");
    expect(source).not.toContain("token=");
  });
});
