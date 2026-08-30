import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

import {
  evaluateTrustedProxyReadiness,
  resolveTrustedProxyConfig,
} from "../../../apps/api/src/services/trustedProxyConfig";

describe("Milestone 27.2 trusted proxy / forwarded header handling", () => {
  it("uses safe private-network defaults",()=> {
    expect(
      resolveTrustedProxyConfig(
        {},
      ),
    ).toEqual([
      "loopback",
      "linklocal",
      "uniquelocal",
    ]);
  });

  it("supports explicit trusted proxy configuration",()=> {
    expect(
      resolveTrustedProxyConfig({
        SPORTSOS_TRUST_PROXY:
          "127.0.0.1,172.16.0.0/12",
      }),
    ).toEqual([
      "127.0.0.1",
      "172.16.0.0/12",
    ]);
  });

  it("documents forwarded headers",()=> {
    const result =
      evaluateTrustedProxyReadiness(
        {},
      );

    expect(
      result.forwardedHeaders.proto,
    ).toBe(
      "x-forwarded-proto",
    );

    expect(
      result.forwardedHeaders.host,
    ).toBe(
      "x-forwarded-host",
    );

    expect(
      result.forwardedHeaders.for,
    ).toBe(
      "x-forwarded-for",
    );
  });

  it("configures Fastify trustProxy",()=> {
    const app =
      fs.readFileSync(
        new URL(
          "../../../apps/api/src/app.ts",
          import.meta.url,
        ),
        "utf8",
      );

    expect(app).toContain(
      "trustProxy",
    );

    expect(app).toContain(
      "resolveTrustedProxyConfig",
    );
  });
});
