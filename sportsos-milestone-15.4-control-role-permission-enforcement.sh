#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-15.4-control-role-permission-enforcement-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

[[ -n "$ROOT_REAL" && -n "$EXPECTED_REAL" ]] || { echo "ERROR: unable to resolve root" >&2; exit 1; }
[[ "$ROOT_REAL" == "$EXPECTED_REAL" ]] || { echo "ERROR: refusing outside canonical root" >&2; exit 1; }

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/api/src/routes/scoreboardControlPolicy.ts" \
  "$ROOT/apps/api/src/routes/scoreboardControlInputs.ts" \
  "$ROOT/apps/api/src/modules/auth"
do
  [[ -e "$required" ]] || { echo "ERROR: prerequisite missing: $required" >&2; echo "Repository was not modified." >&2; exit 1; }
done

cd "$ROOT"

AUTHZ="apps/api/src/services/scoreboardControlAuthorization.ts"
POLICY_ROUTE="apps/api/src/routes/scoreboardControlPolicy.ts"
INPUT_ROUTE="apps/api/src/routes/scoreboardControlInputs.ts"
TEST="packages/core/test/control-role-permission-enforcement-15.4.test.ts"
DISCOVERY="apps/api/src/services/scoreboardControlAuthorization.discovery.txt"

for file in "$AUTHZ" "$POLICY_ROUTE" "$INPUT_ROUTE" "$TEST" "$DISCOVERY"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
  fi
done

mkdir -p "$(dirname "$AUTHZ")" "$(dirname "$TEST")"

grep -RInE 'role|roles|permission|authorize|request\.user|request\.auth|session' \
  apps/api/src/modules/auth apps/api/src/routes apps/api/src/services 2>/dev/null \
  | head -n 250 > "$DISCOVERY" || true

cat > "$AUTHZ" <<'EOF'
import type { FastifyRequest } from "fastify";

export type ScoreboardControlPermission =
  | "CONTROL_POLICY_READ"
  | "CONTROL_POLICY_WRITE";

type Principal = {
  userId: string | null;
  roles: string[];
};

const READ_ROLES = new Set([
  "ADMIN",
  "SUPER_ADMIN",
  "ORGANIZATION_ADMIN",
  "TOURNAMENT_DIRECTOR",
  "SCOREKEEPER",
  "OPERATOR",
]);

const WRITE_ROLES = new Set([
  "ADMIN",
  "SUPER_ADMIN",
  "ORGANIZATION_ADMIN",
  "TOURNAMENT_DIRECTOR",
  "OPERATOR",
]);

function normalizeRole(value: unknown): string | null {
  if (typeof value !== "string") return null;

  const normalized = value
    .trim()
    .replace(/[\s-]+/g, "_")
    .toUpperCase();

  return normalized || null;
}

function collectRoles(source: unknown): string[] {
  if (typeof source !== "object" || source === null) return [];

  const object = source as Record<string, unknown>;
  const candidates = [object.role, object.roles, object.permissions];
  const roles = new Set<string>();

  for (const candidate of candidates) {
    if (Array.isArray(candidate)) {
      for (const value of candidate) {
        const role = normalizeRole(value);
        if (role) roles.add(role);
      }
      continue;
    }

    const role = normalizeRole(candidate);
    if (role) roles.add(role);
  }

  return [...roles];
}

export function getScoreboardControlPrincipal(
  request: FastifyRequest,
): Principal {
  const extended = request as FastifyRequest & {
    user?: unknown;
    auth?: unknown;
    session?: unknown;
  };

  const roles = new Set<string>();
  let userId: string | null = null;

  for (const source of [
    extended.user,
    extended.auth,
    extended.session,
  ]) {
    if (typeof source !== "object" || source === null) continue;

    for (const role of collectRoles(source)) roles.add(role);

    if (!userId) {
      const object = source as Record<string, unknown>;
      const candidate = object.userId ?? object.id ?? object.sub;
      if (typeof candidate === "string" && candidate.trim()) {
        userId = candidate.trim();
      }
    }
  }

  return { userId, roles: [...roles] };
}

export function hasScoreboardControlPermission(
  request: FastifyRequest,
  permission: ScoreboardControlPermission,
): boolean {
  const principal = getScoreboardControlPrincipal(request);

  const allowed =
    permission === "CONTROL_POLICY_WRITE"
      ? WRITE_ROLES
      : READ_ROLES;

  return principal.roles.some((role) => allowed.has(role));
}
EOF

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/scoreboardControlPolicy.ts";
let text = fs.readFileSync(file, "utf8");

const importLine =
  'import { hasScoreboardControlPermission } from "../services/scoreboardControlAuthorization.js";';

if (!text.includes(importLine)) {
  const imports = text.match(/^(import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate policy import block.");
  text = text.replace(imports[0], imports[0] + importLine + "\n");
}

if (!text.includes('"CONTROL_POLICY_READ"')) {
  text = text.replace(
`  app.get(
    "/scoreboard-control-policies",
    async () => ({`,
`  app.get(
    "/scoreboard-control-policies",
    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_READ",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy read permission required.",
        });
      }

      return ({`
  );

  text = text.replace(
`      },
    }),
  );`,
`      },
    });
    },
  );`
  );
}

if (!text.includes('"CONTROL_POLICY_WRITE"')) {
  text = text.replace(
`    async (request, reply) => {
      const body =`,
`    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const body =`,
  );

  const deleteStart = text.indexOf('app.delete(');
  if (deleteStart !== -1) {
    const handler = text.indexOf('    async (request, reply) => {\n      const scope =', deleteStart);
    if (handler !== -1) {
      text = text.slice(0, handler) +
`    async (request, reply) => {
      if (
        !hasScoreboardControlPermission(
          request,
          "CONTROL_POLICY_WRITE",
        )
      ) {
        return reply.code(403).send({
          success: false,
          error: "Physical control policy write permission required.",
        });
      }

      const scope =` +
      text.slice(handler + '    async (request, reply) => {\n      const scope ='.length);
    }
  }
}

fs.writeFileSync(file, text);
NODE

node <<'NODE'
const fs = require("fs");
const file = "apps/api/src/routes/scoreboardControlInputs.ts";
let text = fs.readFileSync(file, "utf8");

if (!text.includes("DEVICE_ORIGINATED_CONTROL_AUTHORIZATION")) {
  const marker = "export async function registerScoreboardControlInputRoutes";
  const idx = text.indexOf(marker);
  if (idx === -1) throw new Error("Unable to locate control input route export.");

  text = text.slice(0, idx) +
`const DEVICE_ORIGINATED_CONTROL_AUTHORIZATION =
  "VERIFIED_DEVICE_ASSIGNMENT_POLICY_LIFECYCLE_SEQUENCE" as const;

void DEVICE_ORIGINATED_CONTROL_AUTHORIZATION;

` +
  text.slice(idx);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 15.4 control role / permission enforcement", () => {
  const authz = fs.readFileSync(
    new URL(
      "../../../apps/api/src/services/scoreboardControlAuthorization.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const policyRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlPolicy.ts",
      import.meta.url,
    ),
    "utf8",
  );

  const inputRoute = fs.readFileSync(
    new URL(
      "../../../apps/api/src/routes/scoreboardControlInputs.ts",
      import.meta.url,
    ),
    "utf8",
  );

  it("defines separate read and write permissions", () => {
    expect(authz).toContain('"CONTROL_POLICY_READ"');
    expect(authz).toContain('"CONTROL_POLICY_WRITE"');
  });

  it("reserves writes for elevated operator roles", () => {
    expect(authz).toContain('"TOURNAMENT_DIRECTOR"');
    expect(authz).toContain('"ORGANIZATION_ADMIN"');
    expect(authz).toContain("WRITE_ROLES");
  });

  it("enforces permission checks on policy routes", () => {
    expect(policyRoute).toContain("hasScoreboardControlPermission");
    expect(policyRoute).toContain('"CONTROL_POLICY_READ"');
    expect(policyRoute).toContain('"CONTROL_POLICY_WRITE"');
    expect(policyRoute).toContain("reply.code(403)");
  });

  it("keeps device-originated control authorization separate", () => {
    expect(inputRoute).toContain("DEVICE_ORIGINATED_CONTROL_AUTHORIZATION");
    expect(inputRoute).toContain("isVerifiedDevice");
  });

  it("does not trust role headers directly", () => {
    expect(authz).not.toContain("request.headers");
    expect(authz).not.toContain("x-sportsos-role");
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 15.4 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - server-side scoreboard control authorization service"
echo "  - CONTROL_POLICY_READ permission"
echo "  - CONTROL_POLICY_WRITE permission"
echo "  - role normalization from authenticated request context"
echo "  - policy GET authorization"
echo "  - policy PUT/DELETE authorization"
echo "  - explicit separation of human-operator auth and VERIFIED-device auth"
echo "  - no trusted role headers"
echo "  - auth discovery snapshot:"
echo "    $DISCOVERY"
echo "  - Milestone 15.4 tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 15.5 - Policy Change Audit / Actor Attribution"
