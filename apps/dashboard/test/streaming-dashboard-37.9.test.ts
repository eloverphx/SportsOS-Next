import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pageFile = path.resolve(__dirname, "../app/streaming/page.tsx");
const appShellFile = path.resolve(__dirname, "../components/AppShell.tsx");

describe("M37.9 streaming dashboard", () => {
  it("loads recordings through the authenticated API client", () => {
    const source = readFileSync(pageFile, "utf8");

    expect(source).toContain('api<RecordingsResponse>("/recordings?limit=100")');
    expect(source).toContain("<AuthGate>");
    expect(source).toContain("<AppShell>");
  });

  it("surfaces durable recording lifecycle states", () => {
    const source = readFileSync(pageFile, "utf8");

    for (const status of ["RECORDING", "PROCESSING", "READY", "FAILED", "ARCHIVED"]) {
      expect(source).toContain(`"${status}"`);
    }

    expect(source).toContain("mediaAssetId");
    expect(source).toContain("durationMs");
    expect(source).toContain("gameId");
  });

  it("does not expose protected media through a raw video element", () => {
    const source = readFileSync(pageFile, "utf8");

    expect(source).not.toContain("<video");
    expect(source).not.toContain("token=");
    expect(source).not.toContain("sportsos_token");
  });

  it("replaces the placeholder Streaming navigation link", () => {
    const source = readFileSync(appShellFile, "utf8");

    expect(source).toContain(
      '{ label: "Streaming", href: "/streaming", permission: PERMISSIONS.STREAM_READ }',
    );
    expect(source).not.toContain('{ label: "Streaming", href: "#"');
  });
});
