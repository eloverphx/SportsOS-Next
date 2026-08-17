#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="platform-startup-trace"
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

if (!app.includes("function startupTrace(")) {
  const anchor = "export interface BuildAppOptions {";
  if (!app.includes(anchor)) throw new Error("BuildAppOptions anchor not found.");

  app = app.replace(
    anchor,
`function startupTrace(label: string): void {
  if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
    console.error(\`[sportsos-startup] \${new Date().toISOString()} \${label}\`);
  }
}

${anchor}`
  );
}

function addTraceOnce(search, replacement, label) {
  if (app.includes(replacement)) return;
  if (!app.includes(search)) throw new Error(`App trace anchor not found: ${label}`);
  app = app.replace(search, replacement);
}

addTraceOnce(
  "  await registerPlatformPlugins(app);",
  `  startupTrace("before registerPlatformPlugins");
  await registerPlatformPlugins(app);
  startupTrace("after registerPlatformPlugins");`,
  "registerPlatformPlugins"
);

addTraceOnce(
  `  await app.register(jwt, {
    secret: config.auth.jwtSecret,
  });`,
  `  startupTrace("before jwt register");
  await app.register(jwt, {
    secret: config.auth.jwtSecret,
  });
  startupTrace("after jwt register");`,
  "jwt"
);

addTraceOnce(
  "  await app.register(platformRoutes);",
  `  startupTrace("before platformRoutes");
  await app.register(platformRoutes);
  startupTrace("after platformRoutes");`,
  "platformRoutes"
);

addTraceOnce(
  "  return app;",
  `  startupTrace("buildApp returning");
  return app;`,
  "return app"
);

if (!test.includes("[platform-trace] before dynamic import")) {
  const search = `  beforeAll(async () => {
    const { buildApp } = await import("../src/app.js");

    app = await buildApp({`;

  const replacement = `  beforeAll(async () => {
    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] before dynamic import");
    }

    const { buildApp } = await import("../src/app.js");

    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after dynamic import / before buildApp");
    }

    app = await buildApp({`;

  if (!test.includes(search)) {
    throw new Error("Platform test dynamic import anchor not found.");
  }
  test = test.replace(search, replacement);
}

if (!test.includes("[platform-trace] after buildApp / before test route")) {
  const search = `    });

    app.get("/test/forbidden", async () => {`;

  const replacement = `    });

    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after buildApp / before test route");
    }

    app.get("/test/forbidden", async () => {`;

  if (!test.includes(search)) {
    throw new Error("Platform test buildApp completion anchor not found.");
  }
  test = test.replace(search, replacement);
}

if (!test.includes("[platform-trace] before app.ready")) {
  const search = "    await app.ready();";

  const replacement = `    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] before app.ready");
    }

    await app.ready();

    if (process.env.SPORTSOS_STARTUP_TRACE === "1") {
      console.error("[platform-trace] after app.ready");
    }`;

  if (!test.includes(search)) {
    throw new Error("Platform test app.ready anchor not found.");
  }
  test = test.replace(search, replacement);
}

fs.writeFileSync(appFile, app);
fs.writeFileSync(testFile, test);
NODE

echo
echo "Startup tracing installed."
echo "Backup: $BACKUP_DIR"
echo
echo "Run:"
echo "  SPORTSOS_STARTUP_TRACE=1 npm run test --workspace=@sportsos/api -- test/platform.test.ts --reporter=verbose"
echo
