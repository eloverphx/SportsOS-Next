import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const root = path.resolve(__dirname, "../../..");

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

describe("Milestone 30 production operations dashboard", () => {
  it("keeps the protected operations API and dashboard wired through compose", () => {
    const compose = read("docker-compose.yml");

    expect(compose).toContain("SPORTSOS_OPERATIONS_STATUS_API_ENABLED");
    expect(compose).toContain("SPORTSOS_OPERATIONS_STATUS_TOKEN");
    expect(compose).toContain("SPORTSOS_OPERATIONS_DASHBOARD_ENABLED");
    expect(compose).toContain("SPORTSOS_API_INTERNAL_URL");
    expect(compose).toContain("/mnt/user/appdata/SportsOS-Next/data:/app/data");
  });

  it("normalizes generated operations status permissions for the API runtime", () => {
    const script = read("scripts/operations-status-snapshot.sh");

    expect(script).toContain("SPORTSOS_M30_2_2_STATUS_PERMISSION_NORMALIZATION");
    expect(script).toContain('chmod 750 "$SPORTSOS_STATUS_PERMISSION_DIR"');
    expect(script).toContain('chmod 640 "$status_file"');
    expect(script).toContain('chown "$SPORTSOS_STATUS_RUNTIME_UID:$SPORTSOS_STATUS_RUNTIME_GID"');
  });

  it("emits the production Content-Security-Policy from dashboard middleware", () => {
    const middleware = read("apps/dashboard/middleware.ts");

    expect(middleware).toContain("SPORTSOS_M30_3_2_CONTENT_SECURITY_POLICY");
    expect(middleware).toContain('"Content-Security-Policy"');
    expect(middleware).toContain("default-src 'self'");
    expect(middleware).toContain("frame-ancestors 'none'");
    expect(middleware).toContain("object-src 'none'");
    expect(middleware).toContain("https://api.crashthenet.online");
    expect(middleware).toContain("wss://api.crashthenet.online");
  });
});
