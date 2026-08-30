import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 27.10 external HTTPS production acceptance", () => {
  const rehearsal =
    fs.readFileSync(
      new URL(
        "../../../scripts/production-deployment-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  const proxyContract =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/reverseProxyRouteContract.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const tls =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/tlsCertificateReadiness.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const realtime =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/externalRealtimeReadiness.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const exposure =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/services/publicExposureReadiness.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("retains strict external-live rehearsal mode",()=> {
    expect(rehearsal).toContain(
      "SPORTSOS_REQUIRE_EXTERNAL_LIVE",
    );
    expect(rehearsal).toContain(
      "scripts/tls-certificate-check.sh",
    );
    expect(rehearsal).toContain(
      "scripts/external-health-check.sh",
    );
    expect(rehearsal).toContain(
      "scripts/external-realtime-check.sh",
    );
    expect(rehearsal).toContain(
      "scripts/public-exposure-audit.sh",
    );
  });

  it("retains public reverse proxy route contract",()=> {
    expect(proxyContract).toContain("/api/");
    expect(proxyContract).toContain("/socket.io/");
    expect(proxyContract).toContain("stripApiPrefix");
    expect(proxyContract).toContain("websocketUpgrade");
  });

  it("retains TLS hostname and expiry readiness",()=> {
    expect(tls).toContain("minimumDaysRemaining");
    expect(tls).toContain("https:");
  });

  it("retains WSS realtime readiness",()=> {
    expect(realtime).toContain("wss:");
    expect(realtime).toContain("/socket.io/");
  });

  it("retains public exposure contract",()=> {
    expect(exposure).toContain("/admin");
    expect(exposure).toContain("/debug");
    expect(exposure).toContain("/swagger");
  });
});
