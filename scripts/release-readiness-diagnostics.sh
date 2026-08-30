#!/usr/bin/env bash
set -euo pipefail

API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"

node - "$API_URL" <<'NODE'
const base = process.argv[2];

const endpoints = [
  [
    "Release readiness",
    "/broadcast-coordinator/release-readiness",
  ],
  [
    "Secret/environment validation",
    "/broadcast-coordinator/secret-environment-validation",
  ],
];

for (const [name, path] of endpoints) {
  try {
    const response =
      await fetch(
        `${base}${path}`,
      );

    const json =
      await response.json();

    console.log(`\n=== ${name} ===`);
    console.log(`HTTP ${response.status}`);

    for (
      const check
      of json?.data?.checks ??
      []
    ) {
      console.log(
        `${check.ok ? "PASS" : "FAIL"}  ${check.id}  ${check.message}`,
      );
    }
  } catch (error) {
    console.log(`\n=== ${name} ===`);
    console.log(
      `ERROR ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}
NODE
