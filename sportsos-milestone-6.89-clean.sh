#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.89.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-verification-record-fingerprint"' "$PANEL" || {
  echo "Milestone 6.88 verification record fingerprint is not present." >&2
  exit 1
}

grep -q 'function verificationRecordFingerprint(' "$PANEL" || {
  echo "Verification record fingerprint helper is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.89-${STAMP}"

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

if (!text.includes("type FrozenVerificationRecord = {")) {
  const anchor = `type CopiedHandoffSnapshot = {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("CopiedHandoffSnapshot anchor not found");

  const typeBlock = `type FrozenVerificationRecord = {
  readonly fingerprint: string;
  readonly handoffFingerprint: string;
  readonly verificationStatus: HandoffSnapshotVerification;
  readonly verifiedAt: string | null;
  readonly capturedAt: string;
  readonly shareUrl: string;
};

`;

  text = text.slice(0, idx) + typeBlock + text.slice(idx);
}

if (!text.includes("const [frozenVerificationRecord, setFrozenVerificationRecord]")) {
  const anchor = `  const [handoffSnapshotVerification, setHandoffSnapshotVerification] =
    useState<HandoffSnapshotVerification>("IDLE");`;

  if (!text.includes(anchor)) {
    throw new Error("handoffSnapshotVerification state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [frozenVerificationRecord, setFrozenVerificationRecord] =
    useState<FrozenVerificationRecord | null>(null);`,
  );
}

if (!text.includes("function freezeVerificationRecord(")) {
  const anchor = "function verificationRecordFingerprint(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("verificationRecordFingerprint anchor not found");

  const helper = `function freezeVerificationRecord(
  snapshot: CopiedHandoffSnapshot,
): FrozenVerificationRecord {
  return {
    fingerprint: verificationRecordFingerprint(snapshot),
    handoffFingerprint: snapshot.fingerprint,
    verificationStatus: snapshot.verificationStatus,
    verifiedAt: snapshot.verifiedAt,
    capturedAt: snapshot.capturedAt,
    shareUrl: snapshot.shareUrl,
  };
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

const verifyAnchor = `    setCopiedHandoffSnapshot({
      ...copiedHandoffSnapshot,
      verificationStatus,
      verifiedAt:
        verificationStatus === "VERIFIED"
          ? new Date().toISOString()
          : null,
    });`;

if (text.includes(verifyAnchor)) {
  text = text.replace(
    verifyAnchor,
    `    const verifiedSnapshot: CopiedHandoffSnapshot = {
      ...copiedHandoffSnapshot,
      verificationStatus,
      verifiedAt:
        verificationStatus === "VERIFIED"
          ? new Date().toISOString()
          : null,
    };

    setCopiedHandoffSnapshot(verifiedSnapshot);
    setFrozenVerificationRecord(
      freezeVerificationRecord(verifiedSnapshot),
    );`,
  );
} else if (!text.includes("freezeVerificationRecord(verifiedSnapshot)")) {
  throw new Error("6.87 verification snapshot update anchor not found");
}

if (!text.includes("setFrozenVerificationRecord(null);")) {
  const anchor = `      setCopiedHandoffSnapshot(null);
      setHandoffReceiptCopyStatus("ERROR");`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff copy failure reset anchor not found");
  }

  text = text.replace(
    anchor,
    `      setCopiedHandoffSnapshot(null);
      setFrozenVerificationRecord(null);
      setHandoffReceiptCopyStatus("ERROR");`,
  );
}

if (!text.includes('data-testid="director-audit-export-frozen-verification-record"')) {
  const anchor = `        {copiedHandoffSnapshot &&
        copiedHandoffSnapshot.verificationStatus !== "IDLE" ? (
          <span
            className="scheduleAuditVerificationRecordFingerprint"
            data-testid="director-audit-export-verification-record-fingerprint"
          >
            Verification record fingerprint{" "}
            <code>{verificationRecordFingerprint(copiedHandoffSnapshot)}</code>
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Verification record fingerprint UI anchor not found");
  }

  text = text.replace(
    anchor,
    `        {frozenVerificationRecord ? (
          <span
            className="scheduleAuditVerificationRecordFingerprint"
            data-testid="director-audit-export-verification-record-fingerprint"
          >
            Verification record fingerprint{" "}
            <code>{frozenVerificationRecord.fingerprint}</code>
          </span>
        ) : null}

        {frozenVerificationRecord ? (
          <span
            className="scheduleAuditFrozenVerificationRecord"
            data-testid="director-audit-export-frozen-verification-record"
          >
            Verification record frozen for handoff fingerprint{" "}
            <code>{frozenVerificationRecord.handoffFingerprint}</code>
          </span>
        ) : null}`,
  );
}

const copyAnchor = `        {copiedHandoffSnapshot &&
        copiedHandoffSnapshot.verificationStatus !== "IDLE" ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-copy-verification-record"
            onClick={() =>
              void copyPlainText(
                [
                  ...copiedHandoffVerificationLines(
                    copiedHandoffSnapshot,
                  ),
                  \`Verification record fingerprint: \${verificationRecordFingerprint(
                    copiedHandoffSnapshot,
                  )}\`,
                ].join("\\n"),
              )
            }
          >
            Copy verification record
          </button>
        ) : null}`;

if (text.includes(copyAnchor)) {
  text = text.replace(
    copyAnchor,
    `        {copiedHandoffSnapshot &&
        frozenVerificationRecord ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-copy-verification-record"
            onClick={() =>
              void copyPlainText(
                [
                  ...copiedHandoffVerificationLines(
                    copiedHandoffSnapshot,
                  ),
                  \`Verification record fingerprint: \${frozenVerificationRecord.fingerprint}\`,
                ].join("\\n"),
              )
            }
          >
            Copy verification record
          </button>
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

describe("Tournament scheduling 6.89 verification record freeze", () => {
  it("models an immutable verification record", () => {
    expect(panel).toContain("type FrozenVerificationRecord = {");
    expect(panel).toContain("readonly fingerprint: string");
    expect(panel).toContain("readonly handoffFingerprint: string");
    expect(panel).toContain(
      "readonly verificationStatus: HandoffSnapshotVerification",
    );
    expect(panel).toContain("readonly verifiedAt: string | null");
    expect(panel).toContain("readonly capturedAt: string");
    expect(panel).toContain("readonly shareUrl: string");
  });

  it("freezes verification record after verification completes", () => {
    expect(panel).toContain(
      "const verifiedSnapshot: CopiedHandoffSnapshot = {",
    );
    expect(panel).toContain(
      "setFrozenVerificationRecord(",
    );
    expect(panel).toContain(
      "freezeVerificationRecord(verifiedSnapshot)",
    );
  });

  it("derives the frozen verification fingerprint once", () => {
    expect(panel).toContain(
      "function freezeVerificationRecord(",
    );
    expect(panel).toContain(
      "fingerprint: verificationRecordFingerprint(snapshot)",
    );
    expect(panel).toContain(
      "handoffFingerprint: snapshot.fingerprint",
    );
  });

  it("renders the frozen verification record fingerprint", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-verification-record-fingerprint"',
    );
    expect(panel).toContain(
      "<code>{frozenVerificationRecord.fingerprint}</code>",
    );
  });

  it("shows which handoff fingerprint the verification record belongs to", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-frozen-verification-record"',
    );
    expect(panel).toContain(
      "<code>{frozenVerificationRecord.handoffFingerprint}</code>",
    );
  });

  it("copies the frozen verification fingerprint instead of recalculating it", () => {
    expect(panel).toContain(
      "Verification record fingerprint: ${frozenVerificationRecord.fingerprint}",
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
echo " SportsOS Milestone 6.89"
echo " Verification Record Freeze"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  freezes verification record after snapshot verification"
echo "  stores verification fingerprint once"
echo "  binds frozen verification record to handoff fingerprint"
echo "  UI uses frozen verification fingerprint"
echo "  copied verification record uses frozen fingerprint"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
