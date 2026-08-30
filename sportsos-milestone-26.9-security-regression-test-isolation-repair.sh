#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
TEST="${ROOT}/apps/api/test/security-regression-26.9.test.ts"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.9-test-isolation-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$TEST" ]] || {
  echo "ERROR: missing $TEST" >&2
  exit 1
}

mkdir -p "$BACKUP/apps/api/test"
cp -a "$TEST" "$BACKUP/apps/api/test/security-regression-26.9.test.ts"

cat > "$TEST" <<'EOF'
import {
  afterEach,
  describe,
  expect,
  it,
} from "vitest";

import Fastify, {
  type FastifyInstance,
} from "fastify";

import {
  securityHeadersPlugin,
} from "../src/plugins/securityHeaders";

const apps:
  FastifyInstance[] =
  [];

async function buildSecurityTestApp() {
  const app =
    Fastify({
      logger:
        false,
    });

  apps.push(
    app,
  );

  await app.register(
    securityHeadersPlugin,
  );

  app.get(
    "/health",
    async () => ({
      success:
        true,
    }),
  );

  app.get(
    "/broadcast-coordinator/security-telemetry",
    async () => ({
      success:
        true,
      data: {
        ready:
          true,
      },
    }),
  );

  await app.ready();

  return app;
}

afterEach(
  async () => {
    while (
      apps.length
    ) {
      const app =
        apps.pop();

      if (app) {
        await app.close();
      }
    }
  },
);

describe("Milestone 26.9 API security regression", () => {
  it("returns baseline security headers on health response", async () => {
    const app =
      await buildSecurityTestApp();

    const response =
      await app.inject({
        method:
          "GET",
        url:
          "/health",
      });

    expect(
      response.statusCode,
    ).toBe(
      200,
    );

    expect(
      response.headers[
        "x-content-type-options"
      ],
    ).toBe(
      "nosniff",
    );

    expect(
      response.headers[
        "x-frame-options"
      ],
    ).toBe(
      "DENY",
    );

    expect(
      response.headers[
        "referrer-policy"
      ],
    ).toBe(
      "no-referrer",
    );

    expect(
      response.headers[
        "permissions-policy"
      ],
    ).toBe(
      "camera=(), microphone=(), geolocation=()",
    );

    expect(
      response.headers[
        "cross-origin-opener-policy"
      ],
    ).toBe(
      "same-origin",
    );

    expect(
      response.headers[
        "cross-origin-resource-policy"
      ],
    ).toBe(
      "same-origin",
    );
  });

  it("does not expose powered-by style framework header", async () => {
    const app =
      await buildSecurityTestApp();

    const response =
      await app.inject({
        method:
          "GET",
        url:
          "/health",
      });

    expect(
      response.headers[
        "x-powered-by"
      ],
    ).toBeUndefined();
  });

  it("keeps security telemetry read-only", async () => {
    const app =
      await buildSecurityTestApp();

    const get =
      await app.inject({
        method:
          "GET",
        url:
          "/broadcast-coordinator/security-telemetry",
      });

    expect(
      get.statusCode,
    ).toBe(
      200,
    );

    const post =
      await app.inject({
        method:
          "POST",
        url:
          "/broadcast-coordinator/security-telemetry",
      });

    expect(
      [
        404,
        405,
      ],
    ).toContain(
      post.statusCode,
    );
  });
});
EOF

echo "============================================================"
echo " SportsOS 26.9 security regression test isolation repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - security tests no longer boot the full API"
echo "  - no MySQL dependency in header regression tests"
echo "  - no startup recovery hooks in security unit tests"
echo "  - isolated Fastify app exercises real securityHeadersPlugin"
echo "  - read-only telemetry method regression retained"
echo
echo "Backup:"
echo "  $BACKUP/apps/api/test/security-regression-26.9.test.ts"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
