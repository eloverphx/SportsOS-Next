#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
REL_ROUTE="apps/api/src/routes/broadcastSessionCoordinator.ts"
ROUTE="${ROOT}/${REL_ROUTE}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.3-mysql-readiness-type-repair-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

[[ -f "$ROUTE" ]] || {
  echo "ERROR: missing $ROUTE" >&2
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$REL_ROUTE")"
cp -a "$REL_ROUTE" "$BACKUP/$REL_ROUTE"

node <<'NODE'
const fs = require("fs");
const file = "/mnt/user/appdata/SportsOS-Next/apps/api/src/routes/broadcastSessionCoordinator.ts";
let s = fs.readFileSync(file, "utf8");

if (!s.includes('from "mysql2/promise"')) {
  const imports = s.match(/^(?:import[\s\S]*?;\n)+/);
  if (!imports) throw new Error("Unable to locate import block.");

  s = s.replace(
    imports[0],
    imports[0] + 'import mysql from "mysql2/promise";\n'
  );
}

const oldBlock = `      let mysqlReachable =
        false;

      try {
        await app.mysql.query(
          "SELECT 1",
        );

        mysqlReachable =
          true;
      } catch {
        mysqlReachable =
          false;
      }`;

const newBlock = `      let mysqlReachable =
        false;

      try {
        const connection =
          await mysql.createConnection({
            host:
              process.env.MYSQL_HOST ??
              "mysql",
            port:
              Number(
                process.env.MYSQL_PORT ??
                3306,
              ),
            database:
              process.env.MYSQL_DATABASE,
            user:
              process.env.MYSQL_USER,
            password:
              process.env.MYSQL_PASSWORD,
          });

        try {
          await connection.query(
            "SELECT 1",
          );

          mysqlReachable =
            true;
        } finally {
          await connection.end();
        }
      } catch {
        mysqlReachable =
          false;
      }`;

if (!s.includes(oldBlock)) {
  throw new Error("25.3 app.mysql readiness block not found.");
}

s = s.replace(oldBlock, newBlock);

if (s.includes("app.mysql")) {
  throw new Error("app.mysql reference remains after repair.");
}

fs.writeFileSync(file, s);
console.log("25.3 MySQL readiness repaired to use mysql2/promise.");
NODE

echo
echo "============================================================"
echo " SportsOS Milestone 25.3 MySQL readiness type repair installed"
echo "============================================================"
echo "Changed:"
echo "  - removed unsupported app.mysql access"
echo "  - uses mysql2/promise createConnection"
echo "  - SELECT 1 still performs the runtime readiness check"
echo "  - closes readiness connection cleanly"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
