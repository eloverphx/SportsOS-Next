import { describe, expect, it } from "vitest";

import { buildDashboardContentSecurityPolicy } from "../../../apps/dashboard/lib/contentSecurityPolicy";

describe("Milestone 36.10.2.5 dashboard CSP CI E2E compatibility", () => {
  it("keeps the production API and websocket origins allowed", () => {
    const policy = buildDashboardContentSecurityPolicy({
      NODE_ENV: "production",
      NEXT_PUBLIC_API_URL: "https://api.crashthenet.online",
    });

    expect(policy).toContain(
      "connect-src 'self' https://api.crashthenet.online wss://api.crashthenet.online",
    );
    expect(policy).toContain("upgrade-insecure-requests");
    expect(policy).not.toContain("'unsafe-eval'");
  });

  it("allows the configured CI loopback API without forcing it to HTTPS", () => {
    const policy = buildDashboardContentSecurityPolicy({
      NODE_ENV: "production",
      NEXT_PUBLIC_API_URL: "http://127.0.0.1:4001",
    });

    expect(policy).toContain("connect-src 'self' http://127.0.0.1:4001 ws://127.0.0.1:4001");
    expect(policy).not.toContain("upgrade-insecure-requests");
    expect(policy).not.toContain("'unsafe-eval'");
  });

  it("permits Next development transforms only outside production", () => {
    const policy = buildDashboardContentSecurityPolicy({
      NODE_ENV: "development",
      NEXT_PUBLIC_API_URL: "http://127.0.0.1:4001",
    });

    expect(policy).toContain("script-src 'self' 'unsafe-inline' 'unsafe-eval'");
  });
});
