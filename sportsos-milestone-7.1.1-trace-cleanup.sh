#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.1.1-trace-cleanup"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

APP="apps/api/src/app.ts"
TEST="apps/api/test/platform.test.ts"

for file in "$APP" "$TEST"; do
  [[ -f "$file" ]] || { echo "ERROR: missing $file" >&2; exit 1; }
done

mkdir -p "$BACKUP_DIR/$(dirname "$APP")" "$BACKUP_DIR/$(dirname "$TEST")"
cp -a "$APP" "$BACKUP_DIR/$APP"
cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const appFile = "apps/api/src/app.ts";
const testFile = "apps/api/test/platform.test.ts";

let app = fs.readFileSync(appFile, "utf8");
let test = fs.readFileSync(testFile, "utf8");

app = app.replace(
`function startupTrace(label: string): void {
  if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
    console.error(\`[sportsos-startup] \${new Date().toISOString()} \${label}\`);
  }
}

`,
""
);

const traceLines = [
  '  startupTrace("before registerPlatformPlugins");\n',
  '  startupTrace("after registerPlatformPlugins");\n',
  '  startupTrace("before jwt register");\n',
  '  startupTrace("after jwt register");\n',
  '  startupTrace("before platformRoutes");\n',
  '  startupTrace("after platformRoutes");\n',
  '  startupTrace("buildApp returning");\n',
];

for (const line of traceLines) {
  app = app.replace(line, "");
}

test = test.replace(
`    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] before dynamic import");
    }

`,
""
);

test = test.replace(
`    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after dynamic import / before buildApp");
    }

`,
""
);

test = test.replace(
`    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after buildApp / before test route");
    }

`,
""
);

test = test.replace(
`    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] before app.ready");
    }

`,
""
);

test = test.replace(
`
    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after app.ready");
    }`,
""
);

if (!app.includes('readonly routeScope?: "all" | "platform";')) {
  throw new Error("Expected routeScope isolation is missing; refusing cleanup.");
}

if (!test.includes('routeScope: "platform"')) {
  throw new Error("Expected platform routeScope test isolation is missing; refusing cleanup.");
}

fs.writeFileSync(appFile, app);
fs.writeFileSync(testFile, test);
NODE

if grep -Rq 'SPORTSOS_STARTUP_TRACE\|platform-trace\|sportsos-startup' "$APP" "$TEST"; then
  echo "ERROR: diagnostic trace markers remain after cleanup." >&2
  exit 1
fi

echo
echo "Milestone 7.1.1 diagnostic trace cleanup complete."
echo
echo "Preserved:"
echo "  - testing override"
echo "  - buildApp routeScope=all|platform"
echo "  - platform.test.ts routeScope=platform"
echo
echo "Removed:"
echo "  - SPORTSOS_STARTUP_TRACE diagnostic helper"
echo "  - temporary startup console tracing"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Validate:"
echo "  npm run typecheck && npm test"
