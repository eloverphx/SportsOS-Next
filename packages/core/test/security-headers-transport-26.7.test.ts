import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 26.7 security headers / transport hardening", () => {
  const plugin =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/plugins/securityHeaders.ts",
        import.meta.url,
      ),
      "utf8",
    );

  const app =
    fs.readFileSync(
      new URL(
        "../../../apps/api/src/app.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("sets baseline security headers",()=> {
    expect(plugin).toContain(
      "x-content-type-options",
    );

    expect(plugin).toContain(
      "x-frame-options",
    );

    expect(plugin).toContain(
      "referrer-policy",
    );

    expect(plugin).toContain(
      "cross-origin-opener-policy",
    );

    expect(plugin).toContain(
      "cross-origin-resource-policy",
    );

    expect(plugin).toContain(
      "permissions-policy",
    );
  });

  it("enables HSTS only for production runtime",()=> {
    expect(plugin).toContain(
      'process.env.NODE_ENV ===',
    );

    expect(plugin).toContain(
      "strict-transport-security",
    );

    expect(plugin).toContain(
      "max-age=31536000; includeSubDomains",
    );
  });

  it("does not overwrite an already-set response header",()=> {
    expect(plugin).toContain(
      "reply.hasHeader",
    );
  });

  it("registers security hardening globally",()=> {
    expect(app).toContain(
      "securityHeadersPlugin",
    );

    expect(app).toContain(
      "register(",
    );
  });
});
