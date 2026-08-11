#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.90.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-frozen-verification-record"' "$PANEL" || {
  echo "Milestone 6.89 frozen verification record is not present." >&2
  exit 1
}

grep -q 'type FrozenVerificationRecord = {' "$PANEL" || {
  echo "FrozenVerificationRecord type is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.90-${STAMP}"

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

if (!text.includes("function handoffVerificationBundleLines(")) {
  const anchor = "function freezeVerificationRecord(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("freezeVerificationRecord anchor not found");

  const helper = `function handoffVerificationBundleLines(input: {
  readonly snapshot: CopiedHandoffSnapshot;
  readonly verification: FrozenVerificationRecord;
}): string[] {
  return [
    "SportsOS Schedule Audit Handoff Verification Bundle",
    \`Handoff fingerprint: \${input.snapshot.fingerprint}\`,
    \`Handoff captured at: \${input.snapshot.capturedAt}\`,
    \`Handoff URL: \${input.snapshot.shareUrl}\`,
    \`Evidence fingerprint: \${input.snapshot.evidenceFingerprint}\`,
    \`Recovery state: \${input.snapshot.recoveryState}\`,
    \`Handoff state: \${input.snapshot.handoffState}\`,
    \`Current trust: \${input.snapshot.currentTrust}\`,
    \`Verification status: \${input.verification.verificationStatus}\`,
    \`Verification time: \${input.verification.verifiedAt ?? "not verified"}\`,
    \`Verification record fingerprint: \${input.verification.fingerprint}\`,
  ];
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

if (!text.includes("const copyHandoffVerificationBundle = useCallback(")) {
  const anchor = `  const verifyCopiedHandoffSnapshot = useCallback(() => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("verifyCopiedHandoffSnapshot anchor not found");

  const callback = `  const copyHandoffVerificationBundle = useCallback(async () => {
    if (!copiedHandoffSnapshot || !frozenVerificationRecord) return;

    await copyPlainText(
      handoffVerificationBundleLines({
        snapshot: copiedHandoffSnapshot,
        verification: frozenVerificationRecord,
      }).join("\\n"),
    );
  }, [copiedHandoffSnapshot, frozenVerificationRecord]);

`;

  text = text.slice(0, idx) + callback + text.slice(idx);
}

if (!text.includes('data-testid="director-audit-export-copy-handoff-verification-bundle"')) {
  const anchor = `        {frozenVerificationRecord ? (
          <span
            className="scheduleAuditFrozenVerificationRecord"
            data-testid="director-audit-export-frozen-verification-record"
          >
            Verification record frozen for handoff fingerprint{" "}
            <code>{frozenVerificationRecord.handoffFingerprint}</code>
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Frozen verification record UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {copiedHandoffSnapshot &&
        frozenVerificationRecord ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-copy-handoff-verification-bundle"
            onClick={() => void copyHandoffVerificationBundle()}
          >
            Copy handoff verification bundle
          </button>
        ) : null}

        {copiedHandoffSnapshot &&
        frozenVerificationRecord ? (
          <span
            className="scheduleAuditHandoffVerificationBundle"
            data-testid="director-audit-export-handoff-verification-bundle"
          >
            Bundle includes the frozen handoff snapshot identity and its frozen
            verification proof.
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

describe("Tournament scheduling 6.90 handoff verification bundle export", () => {
  it("formats a combined handoff verification bundle", () => {
    expect(panel).toContain(
      "function handoffVerificationBundleLines(",
    );
    expect(panel).toContain(
      "SportsOS Schedule Audit Handoff Verification Bundle",
    );
    expect(panel).toContain(
      "Handoff fingerprint: ${input.snapshot.fingerprint}",
    );
    expect(panel).toContain(
      "Verification record fingerprint: ${input.verification.fingerprint}",
    );
  });

  it("includes frozen snapshot identity and trust fields", () => {
    expect(panel).toContain(
      "Handoff captured at: ${input.snapshot.capturedAt}",
    );
    expect(panel).toContain(
      "Handoff URL: ${input.snapshot.shareUrl}",
    );
    expect(panel).toContain(
      "Evidence fingerprint: ${input.snapshot.evidenceFingerprint}",
    );
    expect(panel).toContain(
      "Current trust: ${input.snapshot.currentTrust}",
    );
  });

  it("includes frozen verification status and time", () => {
    expect(panel).toContain(
      "Verification status: ${input.verification.verificationStatus}",
    );
    expect(panel).toContain(
      'Verification time: ${input.verification.verifiedAt ?? "not verified"}',
    );
  });

  it("copies the bundle from frozen snapshot and verification records", () => {
    expect(panel).toContain(
      "const copyHandoffVerificationBundle = useCallback",
    );
    expect(panel).toContain(
      "snapshot: copiedHandoffSnapshot",
    );
    expect(panel).toContain(
      "verification: frozenVerificationRecord",
    );
  });

  it("renders a dedicated bundle copy control", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-handoff-verification-bundle"',
    );
    expect(panel).toContain(
      "Copy handoff verification bundle",
    );
  });

  it("explains what the bundle contains", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verification-bundle"',
    );
    expect(panel).toContain(
      "frozen handoff snapshot identity and its frozen",
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
echo " SportsOS Milestone 6.90"
echo " Handoff Verification Bundle Export"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  combines frozen handoff snapshot + frozen verification record"
echo "  bundle includes both integrity fingerprints"
echo "  includes URL, evidence fingerprint, trust, and timestamps"
echo "  dedicated copy handoff verification bundle action"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
