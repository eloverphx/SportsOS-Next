#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.91.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-copy-handoff-verification-bundle"' "$PANEL" || {
  echo "Milestone 6.90 handoff verification bundle is not present." >&2
  exit 1
}

grep -q 'function handoffVerificationBundleLines(' "$PANEL" || {
  echo "Handoff verification bundle formatter is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.91-${STAMP}"

for f in "$PANEL" "$TEST"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

node <<'NODE'
const fs = require("fs");
const path = "apps/dashboard/components/tournament/TournamentScheduleAudit.tsx";
let text = fs.readFileSync(path, "utf8");

if (!text.includes("function handoffVerificationBundleFingerprint(")) {
  const anchor = "function handoffVerificationBundleLines(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("handoffVerificationBundleLines anchor not found");

  const helper = `function handoffVerificationBundleFingerprint(input: {
  readonly snapshot: CopiedHandoffSnapshot;
  readonly verification: FrozenVerificationRecord;
}): string {
  const canonical = handoffVerificationBundleLines(input).join("|");
  let hash = 2166136261;

  for (let index = 0; index < canonical.length; index += 1) {
    hash ^= canonical.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }

  return \`fnv1a32-\${(hash >>> 0).toString(16).padStart(8, "0")}\`;
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

const oldCopy = `    await copyPlainText(
      handoffVerificationBundleLines({
        snapshot: copiedHandoffSnapshot,
        verification: frozenVerificationRecord,
      }).join("\\n"),
    );`;

if (text.includes(oldCopy)) {
  text = text.replace(
    oldCopy,
    `    const bundleInput = {
      snapshot: copiedHandoffSnapshot,
      verification: frozenVerificationRecord,
    };

    const bundleFingerprint =
      handoffVerificationBundleFingerprint(bundleInput);

    await copyPlainText(
      [
        ...handoffVerificationBundleLines(bundleInput),
        \`Bundle fingerprint: \${bundleFingerprint}\`,
      ].join("\\n"),
    );`,
  );
} else if (!text.includes("Bundle fingerprint: ${bundleFingerprint}")) {
  throw new Error("6.90 copy bundle callback body not found");
}

if (!text.includes("const currentVerificationBundleFingerprint = useMemo(")) {
  const anchor = `  const copyHandoffVerificationBundle = useCallback(async () => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("copyHandoffVerificationBundle anchor not found");

  const memo = `  const currentVerificationBundleFingerprint = useMemo(() => {
    if (!copiedHandoffSnapshot || !frozenVerificationRecord) return null;

    return handoffVerificationBundleFingerprint({
      snapshot: copiedHandoffSnapshot,
      verification: frozenVerificationRecord,
    });
  }, [copiedHandoffSnapshot, frozenVerificationRecord]);

`;

  text = text.slice(0, idx) + memo + text.slice(idx);
}

if (!text.includes('data-testid="director-audit-export-handoff-verification-bundle-fingerprint"')) {
  const anchor = `        {copiedHandoffSnapshot &&
        frozenVerificationRecord ? (
          <span
            className="scheduleAuditHandoffVerificationBundle"
            data-testid="director-audit-export-handoff-verification-bundle"
          >
            Bundle includes the frozen handoff snapshot identity and its frozen
            verification proof.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff verification bundle UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {currentVerificationBundleFingerprint ? (
          <span
            className="scheduleAuditHandoffVerificationBundleFingerprint"
            data-testid="director-audit-export-handoff-verification-bundle-fingerprint"
          >
            Verification bundle fingerprint{" "}
            <code>{currentVerificationBundleFingerprint}</code>
          </span>
        ) : null}`,
  );
}

fs.writeFileSync(path, text);
NODE

cat > "$TEST" <<'EOF'
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const panel = readFileSync(
  new URL(
    "../../dashboard/components/tournament/TournamentScheduleAudit.tsx",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.91 verification bundle fingerprint", () => {
  it("defines a deterministic fingerprint for the combined verification bundle", () => {
    expect(panel).toContain(
      "function handoffVerificationBundleFingerprint(",
    );
    expect(panel).toContain(
      "handoffVerificationBundleLines(input).join(\"|\")",
    );
    expect(panel).toContain(
      "Math.imul(hash, 16777619)",
    );
  });

  it("adds the bundle fingerprint to copied verification bundle text", () => {
    expect(panel).toContain(
      "const bundleFingerprint =",
    );
    expect(panel).toContain(
      "handoffVerificationBundleFingerprint(bundleInput)",
    );
    expect(panel).toContain(
      "Bundle fingerprint: ${bundleFingerprint}",
    );
  });

  it("derives an operator-visible current bundle fingerprint", () => {
    expect(panel).toContain(
      "const currentVerificationBundleFingerprint = useMemo",
    );
    expect(panel).toContain(
      "snapshot: copiedHandoffSnapshot",
    );
    expect(panel).toContain(
      "verification: frozenVerificationRecord",
    );
  });

  it("renders the combined bundle fingerprint", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verification-bundle-fingerprint"',
    );
    expect(panel).toContain(
      "<code>{currentVerificationBundleFingerprint}</code>",
    );
  });

  it("preserves both frozen component fingerprints", () => {
    expect(panel).toContain(
      "Handoff fingerprint: ${input.snapshot.fingerprint}",
    );
    expect(panel).toContain(
      "Verification record fingerprint: ${input.verification.fingerprint}",
    );
  });

  it("remains read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Milestone 6.91"
echo " Verification Bundle Fingerprint"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  combined handoff verification bundle gets deterministic fingerprint"
echo "  copied bundle includes top-level bundle fingerprint"
echo "  UI displays bundle fingerprint"
echo "  underlying handoff + verification fingerprints preserved"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
