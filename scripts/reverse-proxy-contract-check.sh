#!/usr/bin/env bash
set -euo pipefail

API_URL="${SPORTSOS_API_URL:-http://127.0.0.1:4001}"
ENDPOINT="${API_URL}/deployment/reverse-proxy-route-contract"

echo "============================================================"
echo " SportsOS Reverse Proxy Contract Check"
echo "============================================================"

node - "$ENDPOINT" <<'NODE'
const endpoint = process.argv[2];

let response;

try {
  response =
    await fetch(endpoint);
} catch (error) {
  console.error(
    `FAIL unable to reach ${endpoint}`,
  );
  process.exit(1);
}

if (!response.ok) {
  console.error(
    `FAIL HTTP ${response.status} ${endpoint}`,
  );
  process.exit(1);
}

const json =
  await response.json();

const contract =
  json?.data;

if (
  typeof contract?.ready !==
    "boolean" ||
  !Array.isArray(
    contract?.routes,
  ) ||
  typeof contract?.requirements !==
    "object"
) {
  console.error(
    "FAIL endpoint did not return reverse proxy route contract shape",
  );
  console.error(
    `Top-level data keys: ${
      contract && typeof contract === "object"
        ? Object.keys(contract).join(", ")
        : "none"
    }`,
  );
  process.exit(1);
}

if (!contract.ready) {
  console.error(
    "FAIL reverse proxy route contract is not ready",
  );
  process.exit(1);
}

for (const route of contract.routes) {
  console.log(
    `PASS  ${route.id}  ${route.publicPath} -> ${route.upstream}${route.websocket ? " [websocket]" : ""}`,
  );
}

for (
  const key
  of [
    "preserveHost",
    "forwardProto",
    "forwardFor",
    "websocketUpgrade",
    "stripApiPrefix",
  ]
) {
  if (
    contract.requirements[key] !==
    true
  ) {
    console.error(
      `FAIL requirement ${key}`,
    );
    process.exit(1);
  }

  console.log(
    `PASS  requirement ${key}`,
  );
}

console.log();
console.log(
  "Reverse proxy route contract PASSED.",
);
NODE
