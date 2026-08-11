#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.92.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-verification-bundle-fingerprint"' "$PANEL" || {
  echo "Milestone 6.91 verification bundle fingerprint is not present." >&2
  exit 1
}

grep -q 'function handoffVerificationBundleFingerprint(' "$PANEL" || {
  echo "Verification bundle fingerprint helper is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.92-${STAMP}"

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

if (!text.includes("type FrozenVerificationBundle = {")) {
  const anchor = `type FrozenVerificationRecord = {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("FrozenVerificationRecord anchor not found");

  const typeBlock = `type FrozenVerificationBundle = {
  readonly fingerprint: string;
  readonly createdAt: string;
  readonly handoffFingerprint: string;
  readonly verificationFingerprint: string;
  readonly text: string;
};

`;

  text = text.slice(0, idx) + typeBlock + text.slice(idx);
}

if (!text.includes("const [frozenVerificationBundle, setFrozenVerificationBundle]")) {
  const anchor = `  const [frozenVerificationRecord, setFrozenVerificationRecord] =
    useState<FrozenVerificationRecord | null>(null);`;

  if (!text.includes(anchor)) {
    throw new Error("frozenVerificationRecord state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [frozenVerificationBundle, setFrozenVerificationBundle] =
    useState<FrozenVerificationBundle | null>(null);`,
  );
}

if (!text.includes("function freezeVerificationBundle(")) {
  const anchor = "function handoffVerificationBundleFingerprint(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("handoffVerificationBundleFingerprint anchor not found");

  const helper = `function freezeVerificationBundle(input: {
  readonly snapshot: CopiedHandoffSnapshot;
  readonly verification: FrozenVerificationRecord;
}): FrozenVerificationBundle {
  const fingerprint = handoffVerificationBundleFingerprint(input);
  const createdAt = new Date().toISOString();
  const text = [
    ...handoffVerificationBundleLines(input),
    \`Bundle created at: \${createdAt}\`,
    \`Bundle fingerprint: \${fingerprint}\`,
  ].join("\\n");

  return {
    fingerprint,
    createdAt,
    handoffFingerprint: input.snapshot.fingerprint,
    verificationFingerprint: input.verification.fingerprint,
    text,
  };
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

const memoStart = `  const currentVerificationBundleFingerprint = useMemo(() => {`;
const memoIdx = text.indexOf(memoStart);
if (memoIdx >= 0) {
  const memoEnd = text.indexOf("\n\n", memoIdx);
  if (memoEnd < 0) throw new Error("currentVerificationBundleFingerprint memo end not found");
  text = text.slice(0, memoIdx) + text.slice(memoEnd + 2);
}

const copyStart = `  const copyHandoffVerificationBundle = useCallback(async () => {`;
const copyIdx = text.indexOf(copyStart);
if (copyIdx < 0) throw new Error("copyHandoffVerificationBundle callback not found");

const copyEndMarker = `\n\n  const verifyCopiedHandoffSnapshot = useCallback`;
const copyEnd = text.indexOf(copyEndMarker, copyIdx);
if (copyEnd < 0) throw new Error("copyHandoffVerificationBundle end anchor not found");

const replacement = `  const copyHandoffVerificationBundle = useCallback(async () => {
    if (!copiedHandoffSnapshot || !frozenVerificationRecord) return;

    const frozenBundle = freezeVerificationBundle({
      snapshot: copiedHandoffSnapshot,
      verification: frozenVerificationRecord,
    });

    setFrozenVerificationBundle(frozenBundle);
    await copyPlainText(frozenBundle.text);
  }, [copiedHandoffSnapshot, frozenVerificationRecord]);`;

text = text.slice(0, copyIdx) + replacement + text.slice(copyEnd);

if (!text.includes("setFrozenVerificationBundle(null);")) {
  const anchor = `      setCopiedHandoffSnapshot(null);
      setFrozenVerificationRecord(null);
      setHandoffReceiptCopyStatus("ERROR");`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff copy failure reset anchor not found");
  }

  text = text.replace(
    anchor,
    `      setCopiedHandoffSnapshot(null);
      setFrozenVerificationRecord(null);
      setFrozenVerificationBundle(null);
      setHandoffReceiptCopyStatus("ERROR");`,
  );
}

const uiAnchor = `        {currentVerificationBundleFingerprint ? (
          <span
            className="scheduleAuditHandoffVerificationBundleFingerprint"
            data-testid="director-audit-export-handoff-verification-bundle-fingerprint"
          >
            Verification bundle fingerprint{" "}
            <code>{currentVerificationBundleFingerprint}</code>
          </span>
        ) : null}`;

if (text.includes(uiAnchor)) {
  text = text.replace(
    uiAnchor,
    `        {frozenVerificationBundle ? (
          <span
            className="scheduleAuditHandoffVerificationBundleFingerprint"
            data-testid="director-audit-export-handoff-verification-bundle-fingerprint"
          >
            Verification bundle fingerprint{" "}
            <code>{frozenVerificationBundle.fingerprint}</code>
          </span>
        ) : null}

        {frozenVerificationBundle ? (
          <span
            className="scheduleAuditFrozenVerificationBundle"
            data-testid="director-audit-export-frozen-verification-bundle"
          >
            Verification bundle frozen{" "}
            {formatWhen(frozenVerificationBundle.createdAt)}
          </span>
        ) : null}`,
  );
} else if (!text.includes('data-testid="director-audit-export-frozen-verification-bundle"')) {
  throw new Error("Verification bundle fingerprint UI anchor not found");
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

describe("Tournament scheduling 6.92 verification bundle freeze", () => {
  it("models an immutable verification bundle", () => {
    expect(panel).toContain("type FrozenVerificationBundle = {");
    expect(panel).toContain("readonly fingerprint: string");
    expect(panel).toContain("readonly createdAt: string");
    expect(panel).toContain("readonly handoffFingerprint: string");
    expect(panel).toContain("readonly verificationFingerprint: string");
    expect(panel).toContain("readonly text: string");
  });

  it("freezes the complete verification bundle before copying", () => {
    expect(panel).toContain(
      "function freezeVerificationBundle(",
    );
    expect(panel).toContain(
      "const frozenBundle = freezeVerificationBundle({",
    );
    expect(panel).toContain(
      "setFrozenVerificationBundle(frozenBundle)",
    );
    expect(panel).toContain(
      "await copyPlainText(frozenBundle.text)",
    );
  });

  it("includes creation time and bundle fingerprint in the frozen text", () => {
    expect(panel).toContain(
      "Bundle created at: ${createdAt}",
    );
    expect(panel).toContain(
      "Bundle fingerprint: ${fingerprint}",
    );
  });

  it("binds the frozen bundle to both component fingerprints", () => {
    expect(panel).toContain(
      "handoffFingerprint: input.snapshot.fingerprint",
    );
    expect(panel).toContain(
      "verificationFingerprint: input.verification.fingerprint",
    );
  });

  it("renders the frozen bundle fingerprint instead of live recalculation", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verification-bundle-fingerprint"',
    );
    expect(panel).toContain(
      "<code>{frozenVerificationBundle.fingerprint}</code>",
    );
  });

  it("shows when the verification bundle was frozen", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-frozen-verification-bundle"',
    );
    expect(panel).toContain(
      "formatWhen(frozenVerificationBundle.createdAt)",
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
echo " SportsOS Milestone 6.92"
echo " Verification Bundle Freeze"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  freezes full verification bundle before copy"
echo "  stores bundle fingerprint once"
echo "  stores bundle creation timestamp"
echo "  binds bundle to handoff + verification fingerprints"
echo "  UI uses frozen bundle fingerprint"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
