#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
MILESTONE="7.1.1-platform-test-isolation"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/${MILESTONE}-${STAMP}"

cd "$ROOT"

APP="apps/api/src/app.ts"
TEST="apps/api/test/platform.test.ts"

for file in "$APP" "$TEST"; do
  [[ -f "$file" ]] || { echo "ERROR: missing $file" >&2; exit 1; }
done

grep -Fq 'readonly realtime?: boolean;' "$APP" || {
  echo "ERROR: expected BuildAppOptions realtime field not found in $APP" >&2
  exit 1
}

grep -Fq 'realtime: false,' "$TEST" || {
  echo "ERROR: expected platform test buildApp options not found in $TEST" >&2
  exit 1
}

mkdir -p "$BACKUP_DIR/$(dirname "$APP")" "$BACKUP_DIR/$(dirname "$TEST")"
cp -a "$APP" "$BACKUP_DIR/$APP"
cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const appFile = "apps/api/src/app.ts";
const testFile = "apps/api/test/platform.test.ts";

let app = fs.readFileSync(appFile, "utf8");
let test = fs.readFileSync(testFile, "utf8");

function replaceOnce(text, label, search, replacement) {
  if (!text.includes(search)) {
    throw new Error(`Expected ${label} anchor not found.`);
  }
  return text.replace(search, replacement);
}

if (!app.includes('readonly routeScope?: "all" | "platform";')) {
  app = replaceOnce(
    app,
    "BuildAppOptions",
`export interface BuildAppOptions {
  readonly logger?: boolean;
  readonly realtime?: boolean;
}`,
`export interface BuildAppOptions {
  readonly logger?: boolean;
  readonly realtime?: boolean;
  /**
   * Limits route registration for focused HTTP contract tests.
   * Production/default behavior remains "all".
   */
  readonly routeScope?: "all" | "platform";
}`
  );
}

const oldRoutes = `  await app.register(platformRoutes);
  await app.register(setupRoutes);
  await app.register(authRoutes);
  await app.register(organizationRoutes);
  await app.register(organizationMemberRoutes);
  await app.register(teamRoutes);
  await app.register(playerRoutes);
  await app.register(seasonRoutes);
  await app.register(gameRoutes);
  await app.register(gameEventRoutes);
  await app.register(penaltyRoutes);
  await app.register(scoreboardDeviceRoutes);
  await app.register(rosterRoutes);
  await app.register(mediaRoutes);
  await app.register(systemRoutes);
  await app.register(gameEngineTelemetryRoutes);
  await app.register(simulationRoutes);`;

const newRoutes = `  await app.register(platformRoutes);

  if ((options.routeScope ?? "all") === "all") {
    await app.register(setupRoutes);
    await app.register(authRoutes);
    await app.register(organizationRoutes);
    await app.register(organizationMemberRoutes);
    await app.register(teamRoutes);
    await app.register(playerRoutes);
    await app.register(seasonRoutes);
    await app.register(gameRoutes);
    await app.register(gameEventRoutes);
    await app.register(penaltyRoutes);
    await app.register(scoreboardDeviceRoutes);
    await app.register(rosterRoutes);
    await app.register(mediaRoutes);
    await app.register(systemRoutes);
    await app.register(gameEngineTelemetryRoutes);
    await app.register(simulationRoutes);
  }`;

if (!app.includes('if ((options.routeScope ?? "all") === "all")')) {
  app = replaceOnce(app, "route registration block", oldRoutes, newRoutes);
}

if (!test.includes('routeScope: "platform"')) {
  test = replaceOnce(
    test,
    "platform test buildApp options",
`    app = await buildApp({
      logger: false,
      realtime: false,
    });`,
`    app = await buildApp({
      logger: false,
      realtime: false,
      routeScope: "platform",
    });`
  );
}

fs.writeFileSync(appFile, app);
fs.writeFileSync(testFile, test);
NODE

echo
echo "Applied focused platform HTTP test isolation."
echo
echo "Changed:"
echo "  $APP"
echo "    - BuildAppOptions gains routeScope: all | platform"
echo "    - default remains all"
echo "    - platformRoutes always register"
echo "    - domain routes register only for routeScope=all"
echo
echo "  $TEST"
echo "    - platform test requests routeScope=platform"
echo "    - existing realtime=false remains"
echo
echo "Production behavior:"
echo "  UNCHANGED. buildApp() defaults to all routes."
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run the focused test first:"
echo
echo "  npm run test --workspace=@sportsos/api -- test/platform.test.ts"
echo
echo "If green:"
echo
echo "  npm run typecheck && npm test"
