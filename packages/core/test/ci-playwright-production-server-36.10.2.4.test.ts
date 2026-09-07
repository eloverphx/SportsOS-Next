import { describe, expect, it } from "vitest";
import fs from "node:fs";

describe("Milestone 36.10.2.4/5.1 CI Playwright production-server repair", () => {
  const config = fs.readFileSync(new URL("../../../playwright.config.ts", import.meta.url), "utf8");

  it("uses a configurable isolated dashboard port", () => {
    expect(config).toContain('const dashboardPort = process.env.PLAYWRIGHT_PORT ?? "4000"');
    expect(config).toContain(
      "process.env.PLAYWRIGHT_BASE_URL ?? `http://127.0.0.1:${dashboardPort}`",
    );
  });

  it("runs the built dashboard with next start in CI", () => {
    expect(config).toContain(
      "npm exec --workspace=@sportsos/dashboard next -- start -p ${dashboardPort}",
    );
    expect(config).toContain(
      "npm exec --workspace=@sportsos/dashboard next -- dev -p ${dashboardPort}",
    );
  });

  it("forces production runtime only for the CI web server", () => {
    expect(config).toContain(
      'NODE_ENV: process.env.CI ? "production" : (process.env.NODE_ENV ?? "development")',
    );
  });

  it("still refuses to reuse an arbitrary existing server in CI", () => {
    expect(config).toContain("reuseExistingServer: !process.env.CI");
  });
});
