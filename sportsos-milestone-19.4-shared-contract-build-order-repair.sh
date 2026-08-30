#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-19.4-shared-contract-build-order-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PACKAGE="package.json"
CORE="packages/core/src/contracts/realtime.ts"
TEST="packages/core/test/shared-contract-build-order-19.4.test.ts"

for required in \
  ".git" \
  "$PACKAGE" \
  "$CORE" \
  "packages/core/package.json" \
  "packages/config/package.json"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PACKAGE" "$TEST"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$TEST")"

node <<'NODE'
const fs = require("fs");

const file = "package.json";
const pkg = JSON.parse(
  fs.readFileSync(file, "utf8"),
);

const expected =
  "npm run ci:prepare && npm run typecheck --workspaces --if-present";

if (pkg.scripts?.typecheck !== expected) {
  pkg.scripts =
    pkg.scripts ?? {};

  pkg.scripts.typecheck =
    expected;
}

fs.writeFileSync(
  file,
  JSON.stringify(
    pkg,
    null,
    2,
  ) + "\n",
);

console.log(
  "Root typecheck now builds shared package declarations before workspace typechecking.",
);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 19.4 shared-contract build-order repair", () => {
  const rootPackage =
    JSON.parse(
      fs.readFileSync(
        new URL(
          "../../../package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as {
      scripts?: {
        typecheck?: string;
        "ci:prepare"?: string;
      };
    };

  const corePackage =
    JSON.parse(
      fs.readFileSync(
        new URL(
          "../../../packages/core/package.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as {
      types?: string;
    };

  const realtime =
    fs.readFileSync(
      new URL(
        "../../../packages/core/src/contracts/realtime.ts",
        import.meta.url,
      ),
      "utf8",
    );

  it("builds shared declarations before workspace typechecking", () => {
    expect(
      rootPackage.scripts?.typecheck,
    ).toBe(
      "npm run ci:prepare && npm run typecheck --workspaces --if-present",
    );
  });

  it("keeps ci:prepare responsible for core/config builds", () => {
    expect(
      rootPackage.scripts?.[
        "ci:prepare"
      ],
    ).toContain(
      "@sportsos/core",
    );

    expect(
      rootPackage.scripts?.[
        "ci:prepare"
      ],
    ).toContain(
      "@sportsos/config",
    );
  });

  it("documents why the build is required", () => {
    expect(
      corePackage.types,
    ).toBe(
      "./dist/index.d.ts",
    );
  });

  it("retains broadcast-session events in core source", () => {
    expect(
      realtime,
    ).toContain(
      '"broadcast-session:updated"',
    );

    expect(
      realtime,
    ).toContain(
      '"broadcast-session:deleted"',
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 19.4 shared-contract build repair"
echo "============================================================"
echo
echo "Fixed:"
echo "  - root typecheck now runs ci:prepare first"
echo "  - @sportsos/core dist declarations rebuilt before dashboard/API checks"
echo "  - @sportsos/config declarations also refreshed"
echo "  - prevents stale shared-contract type errors in future milestones"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
