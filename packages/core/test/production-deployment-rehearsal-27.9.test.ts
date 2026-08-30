import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 27.9 production deployment rehearsal", () => {
  const script =
    fs.readFileSync(
      new URL(
        "../../../scripts/production-deployment-rehearsal.sh",
        import.meta.url,
      ),
      "utf8",
    );

  it("includes local acceptance gates",()=> {
    expect(script).toContain(
      "npm run typecheck && npm test",
    );

    expect(script).toContain(
      "scripts/security-regression-check.sh",
    );

    expect(script).toContain(
      "scripts/release-smoke-test.sh",
    );

    expect(script).toContain(
      "npm run test:e2e:docker",
    );
  });

  it("includes external HTTPS validation gates",()=> {
    expect(script).toContain(
      "scripts/tls-certificate-check.sh",
    );

    expect(script).toContain(
      "scripts/external-health-check.sh",
    );

    expect(script).toContain(
      "scripts/external-realtime-check.sh",
    );

    expect(script).toContain(
      "scripts/public-exposure-audit.sh",
    );
  });

  it("supports strict external-live mode",()=> {
    expect(script).toContain(
      'STRICT_EXTERNAL="${SPORTSOS_REQUIRE_EXTERNAL_LIVE:-0}"',
    );

    expect(script).toContain(
      'if [[ "$STRICT_EXTERNAL" == "1" ]]',
    );
  });

  it("checks deployment readiness endpoints",()=> {
    expect(script).toContain(
      "/deployment/reverse-proxy-route-contract",
    );

    expect(script).toContain(
      "/deployment/tls-certificate-readiness",
    );

    expect(script).toContain(
      "/deployment/external-health-readiness",
    );

    expect(script).toContain(
      "/deployment/external-realtime-readiness",
    );

    expect(script).toContain(
      "/deployment/public-exposure-readiness",
    );
  });
});
