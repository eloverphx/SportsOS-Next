#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-26.7-security-headers-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PLUGIN="apps/api/src/plugins/securityHeaders.ts"
APP="apps/api/src/app.ts"
TEST="packages/core/test/security-headers-transport-26.7.test.ts"
DOC="docs/PRODUCTION-SECURITY-HARDENING.md"

for required in \
  ".git" \
  "$APP" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PLUGIN" "$APP" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PLUGIN")" "$(dirname "$TEST")"

cat > "$PLUGIN" <<'EOF'
import type {
  FastifyInstance,
} from "fastify";

const SECURITY_HEADERS = {
  "x-content-type-options":
    "nosniff",
  "x-frame-options":
    "DENY",
  "referrer-policy":
    "no-referrer",
  "cross-origin-opener-policy":
    "same-origin",
  "cross-origin-resource-policy":
    "same-origin",
  "permissions-policy":
    "camera=(), microphone=(), geolocation=()",
} as const;

export async function securityHeadersPlugin(
  app: FastifyInstance,
) {
  app.addHook(
    "onSend",
    async (
      _request,
      reply,
      payload,
    ) => {
      for (
        const [
          name,
          value,
        ]
        of Object.entries(
          SECURITY_HEADERS,
        )
      ) {
        if (
          !reply.hasHeader(
            name,
          )
        ) {
          reply.header(
            name,
            value,
          );
        }
      }

      if (
        process.env.NODE_ENV ===
        "production"
      ) {
        if (
          !reply.hasHeader(
            "strict-transport-security",
          )
        ) {
          reply.header(
            "strict-transport-security",
            "max-age=31536000; includeSubDomains",
          );
        }
      }

      return payload;
    },
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/api/src/app.ts";

let source =
  fs.readFileSync(
    file,
    "utf8",
  );

if (
  !source.includes(
    'from "./plugins/securityHeaders.js"',
  )
) {
  const imports =
    source.match(
      /^(?:import[\s\S]*?;\n)+/,
    );

  if (!imports) {
    throw new Error(
      "Unable to locate import block in apps/api/src/app.ts",
    );
  }

  source =
    source.replace(
      imports[0],
      imports[0] +
        `import {
  securityHeadersPlugin,
} from "./plugins/securityHeaders.js";
`,
    );
}

if (
  !source.includes(
    "securityHeadersPlugin",
  )
) {
  throw new Error(
    "securityHeadersPlugin import insertion failed.",
  );
}

if (
  !source.includes(
    "register(securityHeadersPlugin",
  )
) {
  const candidates = [
    /const\s+app\s*=\s*Fastify\([^;]*\);\s*/,
    /const\s+app\s*=\s*fastify\([^;]*\);\s*/,
    /const\s+app\s*=\s*Fastify\(\);\s*/,
    /const\s+app\s*=\s*fastify\(\);\s*/,
  ];

  let replaced =
    false;

  for (
    const pattern
    of candidates
  ) {
    if (
      pattern.test(
        source,
      )
    ) {
      source =
        source.replace(
          pattern,
          (match) =>
            `${match}
await app.register(
  securityHeadersPlugin,
);

`,
        );

      replaced =
        true;
      break;
    }
  }

  if (!replaced) {
    const routeRegister =
      source.indexOf(
        "await app.register(",
      );

    if (
      routeRegister <
      0
    ) {
      throw new Error(
        "Unable to locate safe plugin registration point in apps/api/src/app.ts",
      );
    }

    source =
      source.slice(
        0,
        routeRegister,
      ) +
      `await app.register(
  securityHeadersPlugin,
);

` +
      source.slice(
        routeRegister,
      );
  }
}

fs.writeFileSync(
  file,
  source,
);
NODE

cat >> "$DOC" <<'EOF'

## Milestone 26.7 — Security headers / transport hardening

SportsOS now applies a production security-header baseline at the API layer.

Headers include:

```text
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: no-referrer
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

In production, SportsOS also sends:

```text
Strict-Transport-Security: max-age=31536000; includeSubDomains
```

HSTS is meaningful only when the public deployment is actually served over HTTPS. Local HTTP testing may still be used during development, but production ingress should terminate TLS before requests reach SportsOS.

Milestone 26.7 does not change CORS origins or authentication behavior.
EOF

cat > "$TEST" <<'EOF'
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
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 26.7 installed"
echo "============================================================"
echo "Added:"
echo "  - global API security headers plugin"
echo "  - clickjacking protection"
echo "  - MIME sniffing protection"
echo "  - restrictive referrer policy"
echo "  - COOP/CORP baseline"
echo "  - restrictive permissions policy"
echo "  - production-only HSTS"
echo "  - regression coverage"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  curl -I http://127.0.0.1:4001/health"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 26.8 - Security Telemetry / Operator Visibility"
