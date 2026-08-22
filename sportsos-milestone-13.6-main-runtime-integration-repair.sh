#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.6-main-runtime-integration-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/firmware/esp32-scoreboard/src/main.cpp" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateClient.h" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareUpdateDownloader.h" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareInstallPolicy.h" \
  "$ROOT/firmware/esp32-scoreboard/include/FirmwareBootHealth.h"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

MAIN="firmware/esp32-scoreboard/src/main.cpp"
TEST="packages/core/test/controlled-ota-install-reboot-recovery-policy-13.6-repair.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$MAIN")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

cp -a "$MAIN" "$BACKUP_DIR/$MAIN"
[[ -f "$TEST" ]] && cp -a "$TEST" "$BACKUP_DIR/$TEST"

node <<'NODE'
const fs = require("fs");

const file =
  "firmware/esp32-scoreboard/src/main.cpp";

let text =
  fs.readFileSync(file, "utf8");

function ensureInclude(line, afterCandidates) {
  if (text.includes(line)) {
    return;
  }

  for (const anchor of afterCandidates) {
    if (text.includes(anchor)) {
      text =
        text.replace(
          anchor,
          anchor + "\n" + line,
        );
      return;
    }
  }

  const firstInclude =
    text.match(/^#include .*$/m);

  if (!firstInclude || firstInclude.index === undefined) {
    throw new Error(
      `Unable to add include: ${line}`,
    );
  }

  text =
    text.slice(0, firstInclude.index) +
    line +
    "\n" +
    text.slice(firstInclude.index);
}

ensureInclude(
  '#include "FirmwareBootHealth.h"',
  [
    '#include "FirmwareUpdateClient.h"',
    '#include "EnrollmentClient.h"',
  ],
);

ensureInclude(
  '#include "FirmwareInstallPolicy.h"',
  [
    '#include "FirmwareBootHealth.h"',
    '#include "FirmwareUpdateClient.h"',
  ],
);

function ensureUsing(line) {
  if (text.includes(line)) {
    return;
  }

  const matches =
    [...text.matchAll(/^using sportsos::.*?;$/gm)];

  if (matches.length === 0) {
    throw new Error(
      `Unable to add using declaration: ${line}`,
    );
  }

  const last =
    matches[matches.length - 1];

  const insertAt =
    last.index + last[0].length;

  text =
    text.slice(0, insertAt) +
    "\n" +
    line +
    text.slice(insertAt);
}

for (const line of [
  "using sportsos::FirmwareBootHealth;",
  "using sportsos::FirmwareInstallDecision;",
  "using sportsos::FirmwareInstallPolicy;",
  "using sportsos::FirmwareInstallPolicyInput;",
]) {
  ensureUsing(line);
}

if (!text.includes("FirmwareBootHealth bootHealth;")) {
  const globals = [
    "VerifiedRuntimeGate runtimeGate;",
    "FirmwareUpdateClient* firmwareUpdateClient",
    "EnrollmentClient* enrollmentClient",
  ];

  let patched = false;

  for (const anchor of globals) {
    const idx =
      text.indexOf(anchor);

    if (idx === -1) {
      continue;
    }

    const end =
      text.indexOf(";", idx);

    if (end === -1) {
      continue;
    }

    text =
      text.slice(0, end + 1) +
      "\n\nFirmwareBootHealth bootHealth;" +
      text.slice(end + 1);

    patched = true;
    break;
  }

  if (!patched) {
    throw new Error(
      "Unable to place FirmwareBootHealth global.",
    );
  }
}

if (!text.includes("bootHealth.begin();")) {
  const setupStart =
    text.indexOf("void setup()");

  if (setupStart === -1) {
    throw new Error(
      "Unable to locate void setup().",
    );
  }

  const brace =
    text.indexOf("{", setupStart);

  if (brace === -1) {
    throw new Error(
      "Unable to locate setup() opening brace.",
    );
  }

  text =
    text.slice(0, brace + 1) +
    "\n  bootHealth.begin();" +
    text.slice(brace + 1);
}

if (!text.includes("bootHealth.confirmHealthy();")) {
  const startFn =
    text.indexOf(
      "void startAuthoritativeRuntime()",
    );

  if (startFn === -1) {
    throw new Error(
      "Unable to locate startAuthoritativeRuntime().",
    );
  }

  const nextFn =
    text.indexOf(
      "\nvoid ",
      startFn + 5,
    );

  const fnEnd =
    nextFn === -1
      ? text.length
      : nextFn;

  const block =
    text.slice(
      startFn,
      fnEnd,
    );

  const markerCandidates = [
    "runtimeStarted = true;",
    "runtimeStarted =\n      true;",
    "runtimeStarted=true;",
  ];

  let replacementBlock =
    block;

  let inserted = false;

  for (const marker of markerCandidates) {
    if (!replacementBlock.includes(marker)) {
      continue;
    }

    replacementBlock =
      replacementBlock.replace(
        marker,
`${marker}

  if (
      bootHealth.requiresValidation()
  ) {
    bootHealth.confirmHealthy();
  }`,
      );

    inserted = true;
    break;
  }

  if (!inserted) {
    const close =
      replacementBlock.lastIndexOf("}");

    if (close === -1) {
      throw new Error(
        "Unable to locate end of startAuthoritativeRuntime().",
      );
    }

    replacementBlock =
      replacementBlock.slice(0, close) +
`  if (
      bootHealth.requiresValidation()
  ) {
    bootHealth.confirmHealthy();
  }

` +
      replacementBlock.slice(close);
  }

  text =
    text.slice(0, startFn) +
    replacementBlock +
    text.slice(fnEnd);
}

if (!text.includes("FirmwareInstallPolicy::evaluate")) {
  const loopStart =
    text.indexOf("void loop()");

  if (loopStart === -1) {
    throw new Error(
      "Unable to locate void loop().",
    );
  }

  const open =
    text.indexOf("{", loopStart);

  if (open === -1) {
    throw new Error(
      "Unable to locate loop() opening brace.",
    );
  }

  let depth = 0;
  let loopEnd = -1;

  for (let i = open; i < text.length; i += 1) {
    const ch = text[i];

    if (ch === "{") {
      depth += 1;
    } else if (ch === "}") {
      depth -= 1;

      if (depth === 0) {
        loopEnd = i;
        break;
      }
    }
  }

  if (loopEnd === -1) {
    throw new Error(
      "Unable to locate loop() closing brace.",
    );
  }

  const loopBlock =
    text.slice(
      open + 1,
      loopEnd,
    );

  const policyBlock = `

  /*
   * Milestone 13.6:
   * A staged image is activated only when enrollment is verified and
   * the runtime policy considers the reboot safe.
   */
  if (
      firmwareUpdateClient != nullptr &&
      enrollmentClient != nullptr &&
      firmwareUpdateClient->updateAvailable()
  ) {
    const auto& progress =
        firmwareUpdateClient->downloadProgress();

    const bool staged =
        progress.state ==
        sportsos::FirmwareUpdateState::ReadyToInstall;

    const FirmwareInstallPolicyInput
        policyInput{
            enrollmentClient->isVerified(),
            runtimeStarted,
            false,
            firmwareUpdateClient->updateAvailable(),
            staged,
            firmwareUpdateClient->offer().mandatory,
        };

    const auto decision =
        FirmwareInstallPolicy::evaluate(
            policyInput);

    if (
        decision ==
        FirmwareInstallDecision::ReadyToInstall
    ) {
      bootHealth.markPendingValidation();

      delay(100);

      ESP.restart();
    }
  }
`;

  /*
   * Prefer inserting before the final top-level delay() in loop().
   * If no delay exists, insert before the closing brace.
   */
  const delayRegex =
    /\n\s*delay\s*\([^;]*\)\s*;\s*$/m;

  let newLoopBlock;

  const matches =
    [...loopBlock.matchAll(/\n\s*delay\s*\([^;]*\)\s*;/g)];

  if (matches.length > 0) {
    const last =
      matches[matches.length - 1];

    newLoopBlock =
      loopBlock.slice(0, last.index) +
      policyBlock +
      loopBlock.slice(last.index);
  } else {
    newLoopBlock =
      loopBlock +
      policyBlock;
  }

  text =
    text.slice(0, open + 1) +
    newLoopBlock +
    text.slice(loopEnd);
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

describe("Milestone 13.6 main runtime integration repair", () => {
  const main = fs.readFileSync(
    new URL(
      "../../../firmware/esp32-scoreboard/src/main.cpp",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads boot health at startup", () => {
    expect(main).toContain(
      "bootHealth.begin()",
    );
  });

  it("confirms a pending OTA boot after authoritative runtime starts", () => {
    expect(main).toContain(
      "bootHealth.requiresValidation()",
    );

    expect(main).toContain(
      "bootHealth.confirmHealthy()",
    );
  });

  it("evaluates OTA install policy from loop()", () => {
    expect(main).toContain(
      "FirmwareInstallPolicy::evaluate",
    );

    expect(main).toContain(
      "FirmwareInstallDecision::ReadyToInstall",
    );
  });

  it("marks pending validation before reboot", () => {
    const pending =
      main.indexOf(
        "bootHealth.markPendingValidation()",
      );

    const restart =
      main.indexOf(
        "ESP.restart()",
      );

    expect(pending).toBeGreaterThan(-1);
    expect(restart).toBeGreaterThan(pending);
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.6 runtime repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - removed brittle exact runtime-loop anchor dependency"
echo "  - structurally locates void setup() and void loop()"
echo "  - structurally locates loop() closing brace"
echo "  - inserts OTA policy before the final loop delay when present"
echo "  - initializes boot-health tracking"
echo "  - confirms healthy boot after authoritative runtime starts"
echo "  - adds focused regression tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then firmware simulator:"
echo "  node --test firmware/esp32-scoreboard/simulator/test/*.test.js"
echo
echo "Then real firmware compile:"
echo "  bash firmware/esp32-scoreboard/build-in-docker.sh"
