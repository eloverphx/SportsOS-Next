#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.87.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-verification-scope"' "$PANEL" || {
  echo "Milestone 6.86 frozen snapshot verification scope is not present." >&2
  exit 1
}

grep -q 'type HandoffSnapshotVerification = "IDLE" | "VERIFIED" | "FAILED";' "$PANEL" || {
  echo "Handoff snapshot verification state is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.87-${STAMP}"

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

if (!text.includes("readonly verifiedAt: string | null;")) {
  const anchor = `type CopiedHandoffSnapshot = {
  readonly fingerprint: string;
  readonly capturedAt: string;
  readonly shareUrl: string;
  readonly evidenceFingerprint: string;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly exportVerifiedAt: string | null;
  readonly lastTrustReverifiedAt: string | null;
};`;

  if (!text.includes(anchor)) {
    throw new Error("CopiedHandoffSnapshot type anchor not found");
  }

  text = text.replace(
    anchor,
    `type CopiedHandoffSnapshot = {
  readonly fingerprint: string;
  readonly capturedAt: string;
  readonly shareUrl: string;
  readonly evidenceFingerprint: string;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly exportVerifiedAt: string | null;
  readonly lastTrustReverifiedAt: string | null;
  readonly verificationStatus: HandoffSnapshotVerification;
  readonly verifiedAt: string | null;
};`,
  );
}

if (!text.includes('verificationStatus: "IDLE"')) {
  const anchor = `        currentTrust: snapshot.currentTrust,
        exportVerifiedAt: snapshot.exportVerifiedAt,
        lastTrustReverifiedAt: snapshot.lastTrustReverifiedAt,
      });`;

  if (!text.includes(anchor)) {
    throw new Error("Copied handoff snapshot success-state anchor not found");
  }

  text = text.replace(
    anchor,
    `        currentTrust: snapshot.currentTrust,
        exportVerifiedAt: snapshot.exportVerifiedAt,
        lastTrustReverifiedAt: snapshot.lastTrustReverifiedAt,
        verificationStatus: "IDLE",
        verifiedAt: null,
      });`,
  );
}

const verifyAnchor = `    setHandoffSnapshotVerification(
      recalculated === copiedHandoffSnapshot.fingerprint
        ? "VERIFIED"
        : "FAILED",
    );`;

if (text.includes(verifyAnchor)) {
  text = text.replace(
    verifyAnchor,
    `    const verificationStatus: HandoffSnapshotVerification =
      recalculated === copiedHandoffSnapshot.fingerprint
        ? "VERIFIED"
        : "FAILED";

    setHandoffSnapshotVerification(verificationStatus);
    setCopiedHandoffSnapshot({
      ...copiedHandoffSnapshot,
      verificationStatus,
      verifiedAt:
        verificationStatus === "VERIFIED"
          ? new Date().toISOString()
          : null,
    });`,
  );
} else if (!text.includes("verificationStatus === \"VERIFIED\"")) {
  throw new Error("Snapshot verification result anchor not found");
}

if (!text.includes("function copiedHandoffVerificationLines(")) {
  const anchor = "function exportRecoveryReceiptLines(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("exportRecoveryReceiptLines anchor not found");

  const helper = `function copiedHandoffVerificationLines(
  snapshot: CopiedHandoffSnapshot,
): string[] {
  return [
    \`Snapshot verification: \${snapshot.verificationStatus}\`,
    \`Snapshot verified at: \${snapshot.verifiedAt ?? "not verified"}\`,
  ];
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

if (!text.includes('data-testid="director-audit-export-handoff-verification-receipt"')) {
  const anchor = `        {copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditHandoffVerificationScope"
            data-testid="director-audit-export-handoff-verification-scope"
          >
            Verification checks only the frozen copied snapshot and is
            independent of later live investigation changes.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Verification scope UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditHandoffVerificationReceipt"
            data-testid="director-audit-export-handoff-verification-receipt"
          >
            Snapshot verification record:{" "}
            {copiedHandoffSnapshot.verificationStatus}
            {copiedHandoffSnapshot.verifiedAt
              ? \` at \${formatWhen(copiedHandoffSnapshot.verifiedAt)}\`
              : ""}
          </span>
        ) : null}`,
  );
}

if (!text.includes('data-testid="director-audit-export-copy-verification-record"')) {
  const anchor = `        {handoffSnapshotVerification !== "IDLE" ? (
          <span
            className="scheduleAuditHandoffSnapshotVerification"
            data-testid="director-audit-export-handoff-verify-snapshot-status"
            role="status"
            aria-live="polite"
          >
            {handoffSnapshotVerification === "VERIFIED"
              ? "Copied handoff snapshot fingerprint verified."
              : "Copied handoff snapshot fingerprint does not match its frozen snapshot data."}
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Verification status UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {copiedHandoffSnapshot &&
        copiedHandoffSnapshot.verificationStatus !== "IDLE" ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-copy-verification-record"
            onClick={() =>
              void copyPlainText(
                copiedHandoffVerificationLines(
                  copiedHandoffSnapshot,
                ).join("\\n"),
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

describe("Tournament scheduling 6.87 verification result receipt stamp", () => {
  it("stores verification result with the copied handoff snapshot", () => {
    expect(panel).toContain(
      "readonly verificationStatus: HandoffSnapshotVerification",
    );
    expect(panel).toContain(
      "readonly verifiedAt: string | null",
    );
    expect(panel).toContain(
      'verificationStatus: "IDLE"',
    );
    expect(panel).toContain("verifiedAt: null");
  });

  it("updates the copied snapshot only after verification completes", () => {
    expect(panel).toContain(
      "const verificationStatus: HandoffSnapshotVerification",
    );
    expect(panel).toContain(
      "setCopiedHandoffSnapshot({",
    );
    expect(panel).toContain("...copiedHandoffSnapshot");
    expect(panel).toContain(
      'verificationStatus === "VERIFIED"',
    );
    expect(panel).toContain("new Date().toISOString()");
  });

  it("formats a verification record for handoff notes", () => {
    expect(panel).toContain(
      "function copiedHandoffVerificationLines(",
    );
    expect(panel).toContain(
      "Snapshot verification: ${snapshot.verificationStatus}",
    );
    expect(panel).toContain(
      'Snapshot verified at: ${snapshot.verifiedAt ?? "not verified"}',
    );
  });

  it("renders the stored verification result and timestamp", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verification-receipt"',
    );
    expect(panel).toContain(
      "copiedHandoffSnapshot.verificationStatus",
    );
    expect(panel).toContain(
      "formatWhen(copiedHandoffSnapshot.verifiedAt)",
    );
  });

  it("provides a copy action for the verification record", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-verification-record"',
    );
    expect(panel).toContain(
      "copiedHandoffVerificationLines(",
    );
    expect(panel).toContain('.join("\\n")');
  });

  it("preserves frozen-snapshot verification semantics", () => {
    expect(panel).toContain(
      "Verification checks only the frozen copied snapshot",
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
echo " SportsOS Milestone 6.87"
echo " Verification Result Receipt Stamp"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  copied handoff snapshot stores verification status"
echo "  successful verification stores verification timestamp"
echo "  verification result remains attached to frozen snapshot"
echo "  operator-visible verification record"
echo "  verification record can be copied separately"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
