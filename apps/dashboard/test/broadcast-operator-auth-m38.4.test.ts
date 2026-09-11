import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function source(relativePath: string): string {
  return readFileSync(path.resolve(__dirname, relativePath), "utf8");
}

const coordinator = source("../../api/src/routes/broadcastSessionCoordinator.ts");
const goLive = source("../../api/src/routes/goLiveSessions.ts");
const authenticatedApi = source("../lib/authenticated-api.ts");
const operations = source("../app/broadcast/operations/page.tsx");
const focus = source("../app/broadcast/operations/[gameId]/page.tsx");
const shell = source("../components/AppShell.tsx");

describe("M38.4 broadcast operator authentication", () => {
  it("requires stream management permission for coordinator and go-live route modules", () => {
    for (const route of [coordinator, goLive]) {
      expect(route).toContain('app.addHook("preHandler"');
      expect(route).toContain("permission: PERMISSIONS.STREAM_MANAGE");
      expect(route).toContain("await requirePermission(request");
    }
  });

  it("provides a refresh-aware raw response helper for legacy operator response handling", () => {
    expect(authenticatedApi).toContain("export async function authenticatedRequest");
    expect(authenticatedApi).toContain("const refreshedToken = await refreshAuthentication()");
    expect(authenticatedApi).toContain("return response");
    expect(authenticatedApi).toContain("const response = await authenticatedRequest(path, init)");
  });

  it("moves both broadcast operator pages into the authenticated dashboard shell", () => {
    for (const page of [operations, focus]) {
      expect(page).toContain("<AuthGate>");
      expect(page).toContain("<AppShell>");
      expect(page).toContain("authenticatedRequest(");
      expect(page).not.toContain("const API_BASE");
      expect(page).not.toContain("192.168.5.3:4001");
      expect(page).not.toContain("fetch(");
    }
  });

  it("exposes broadcast operations navigation only to stream managers", () => {
    expect(shell).toContain('label: "Broadcast Operations"');
    expect(shell).toContain('href: "/broadcast/operations"');
    expect(shell).toContain("permission: PERMISSIONS.STREAM_MANAGE");
  });
});
