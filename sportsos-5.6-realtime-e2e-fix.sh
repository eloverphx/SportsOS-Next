#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

SPEC="e2e/game-day-scorekeeper.spec.ts"

if [[ ! -f "$SPEC" ]]; then
  echo "Missing Milestone 5.6 spec: $SPEC" >&2
  exit 1
fi

if ! grep -q 'SportsOS is ready for game operation' "$SPEC"; then
  echo "Expected Milestone 5.6 game-day test was not detected." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR=".game-engine-backups/5.6-realtime-fixture-${STAMP}"
mkdir -p "$BACKUP_DIR/e2e"
cp "$SPEC" "$BACKUP_DIR/$SPEC"

node <<'NODE'
const fs = require("fs");
const path = "e2e/game-day-scorekeeper.spec.ts";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("async function installRealtimeFixture")) {
  const anchor = `async function installSession(page: Page) {
  await page.addInitScript((user) => {
    window.localStorage.setItem("sportsos_token", "e2e-scorekeeper-token");
    window.localStorage.setItem("sportsos_user", JSON.stringify(user));
  }, scorekeeper);
}
`;

  if (!text.includes(anchor)) {
    throw new Error("Could not find installSession helper");
  }

  const helper = `

async function installRealtimeFixture(page: Page) {
  let namespaceConnected = false;

  await page.route("**/socket.io/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    const transport = url.searchParams.get("transport");

    if (transport !== "polling") {
      return route.abort();
    }

    if (request.method() === "POST") {
      const body = request.postData() ?? "";

      if (body.includes("40")) {
        namespaceConnected = true;
      }

      return route.fulfill({
        status: 200,
        contentType: "text/plain; charset=UTF-8",
        body: "ok",
      });
    }

    if (!url.searchParams.has("sid")) {
      return route.fulfill({
        status: 200,
        contentType: "text/plain; charset=UTF-8",
        body:
          '0{"sid":"sportsos-e2e-socket","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}',
      });
    }

    return route.fulfill({
      status: 200,
      contentType: "text/plain; charset=UTF-8",
      body: namespaceConnected ? '40{"sid":"sportsos-e2e-namespace"}' : "6",
    });
  });
}
`;

  text = text.replace(anchor, anchor + helper);
}

const callAnchor = `    await installSession(page);

    await page.route("**/auth/me", (route) => json(route, { user: scorekeeper }));`;

if (!text.includes("await installRealtimeFixture(page);")) {
  if (!text.includes(callAnchor)) {
    throw new Error("Could not find session fixture call anchor");
  }

  text = text.replace(
    callAnchor,
`    await installSession(page);
    await installRealtimeFixture(page);

    await page.route("**/auth/me", (route) => json(route, { user: scorekeeper }));`,
  );
}

fs.writeFileSync(path, text);
NODE

echo
echo "============================================="
echo " SportsOS 5.6 Realtime E2E Fixture Repair"
echo "============================================="
echo
echo "Modified:"
echo "  $SPEC"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Added deterministic Socket.IO polling handshake:"
echo "  Engine.IO open packet"
echo "  Socket.IO namespace connect"
echo "  connect event reaches production console"
echo
echo "Production readiness rules were NOT weakened."
echo
echo "Run:"
echo "  npm run test:e2e:docker"
