#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.86.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-verify-snapshot"' "$PANEL" || {
  echo "Milestone 6.85 handoff snapshot verification action is not present." >&2
  exit 1
}

grep -q 'type CopiedHandoffSnapshot = {' "$PANEL" || {
  echo "Copied handoff snapshot model is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.86-${STAMP}"

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

if (!text.includes("readonly recoveryState: ExportRecoveryState;")) {
  const anchor = `type CopiedHandoffSnapshot = {
  readonly fingerprint: string;
  readonly capturedAt: string;
  readonly shareUrl: string;
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
};`,
  );
}

if (!text.includes("evidenceFingerprint: snapshot.evidenceFingerprint")) {
  const anchor = `      setCopiedHandoffSnapshot({
        fingerprint: handoffFingerprint,
        capturedAt: snapshot.capturedAt,
        shareUrl: snapshot.shareUrl,
      });`;

  if (!text.includes(anchor)) {
    throw new Error("Copied handoff snapshot success state anchor not found");
  }

  text = text.replace(
    anchor,
    `      setCopiedHandoffSnapshot({
        fingerprint: handoffFingerprint,
        capturedAt: snapshot.capturedAt,
        shareUrl: snapshot.shareUrl,
        evidenceFingerprint: snapshot.evidenceFingerprint,
        recoveryState: snapshot.recoveryState,
        handoffState: snapshot.handoffState,
        currentTrust: snapshot.currentTrust,
        exportVerifiedAt: snapshot.exportVerifiedAt,
        lastTrustReverifiedAt: snapshot.lastTrustReverifiedAt,
      });`,
  );
}

const start = text.indexOf("  const verifyCopiedHandoffSnapshot = useCallback(() => {");
if (start < 0) throw new Error("verifyCopiedHandoffSnapshot callback not found");

const endMarker = "\n\n  const copyHandoffReceipt = useCallback";
const end = text.indexOf(endMarker, start);
if (end < 0) throw new Error("verifyCopiedHandoffSnapshot callback end not found");

const replacement = `  const verifyCopiedHandoffSnapshot = useCallback(() => {
    if (!copiedHandoffSnapshot) {
      setHandoffSnapshotVerification("FAILED");
      return;
    }

    const verificationSnapshot: HandoffReceiptSnapshot = {
      evidenceFingerprint: copiedHandoffSnapshot.evidenceFingerprint,
      shareUrl: copiedHandoffSnapshot.shareUrl,
      recoveryState: copiedHandoffSnapshot.recoveryState,
      handoffState: copiedHandoffSnapshot.handoffState,
      currentTrust: copiedHandoffSnapshot.currentTrust,
      exportVerifiedAt: copiedHandoffSnapshot.exportVerifiedAt,
      lastTrustReverifiedAt:
        copiedHandoffSnapshot.lastTrustReverifiedAt,
      capturedAt: copiedHandoffSnapshot.capturedAt,
    };

    const recalculated = handoffReceiptFingerprint(verificationSnapshot);

    setHandoffSnapshotVerification(
      recalculated === copiedHandoffSnapshot.fingerprint
        ? "VERIFIED"
        : "FAILED",
    );
  }, [copiedHandoffSnapshot]);`;

text = text.slice(0, start) + replacement + text.slice(end);

if (!text.includes('data-testid="director-audit-export-handoff-verification-scope"')) {
  const anchor = `        {handoffSnapshotVerification !== "IDLE" ? (
          <span
            className="scheduleAuditHandoffSnapshotVerification"
            data-testid="director-audit-export-handoff-verify-snapshot-status"
            role="status"
            aria-live="polite"
          >
            {handoffSnapshotVerification === "VERIFIED"
              ? "Copied handoff snapshot fingerprint verified."
              : "Copied handoff snapshot fingerprint does not match current verification inputs."}
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff snapshot verification status UI anchor not found");
  }

  text = text.replace(
    anchor,
    `        {handoffSnapshotVerification !== "IDLE" ? (
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
        ) : null}

        {copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditHandoffVerificationScope"
            data-testid="director-audit-export-handoff-verification-scope"
          >
            Verification checks only the frozen copied snapshot and is
            independent of later live investigation changes.
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

describe("Tournament scheduling 6.86 verification result snapshot lock", () => {
  it("stores all fingerprint inputs in the copied handoff snapshot", () => {
    expect(panel).toContain("readonly evidenceFingerprint: string");
    expect(panel).toContain("readonly recoveryState: ExportRecoveryState");
    expect(panel).toContain("readonly handoffState: ExportHandoffState");
    expect(panel).toContain("readonly currentTrust: ExportTrustSummary");
    expect(panel).toContain("readonly exportVerifiedAt: string | null");
    expect(panel).toContain("readonly lastTrustReverifiedAt: string | null");
  });

  it("persists the frozen snapshot fingerprint inputs after successful copy", () => {
    expect(panel).toContain(
      "evidenceFingerprint: snapshot.evidenceFingerprint",
    );
    expect(panel).toContain(
      "recoveryState: snapshot.recoveryState",
    );
    expect(panel).toContain(
      "handoffState: snapshot.handoffState",
    );
    expect(panel).toContain(
      "currentTrust: snapshot.currentTrust",
    );
  });

  it("verifies only against stored copied snapshot data", () => {
    expect(panel).toContain(
      "evidenceFingerprint: copiedHandoffSnapshot.evidenceFingerprint",
    );
    expect(panel).toContain(
      "recoveryState: copiedHandoffSnapshot.recoveryState",
    );
    expect(panel).toContain(
      "handoffState: copiedHandoffSnapshot.handoffState",
    );
    expect(panel).toContain(
      "currentTrust: copiedHandoffSnapshot.currentTrust",
    );
  });

  it("removes live-state dependencies from copied snapshot verification", () => {
    expect(panel).toContain(
      "}, [copiedHandoffSnapshot]);",
    );
    expect(panel).not.toContain(
      "current verification inputs.",
    );
  });

  it("explains that verification is independent of later live changes", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verification-scope"',
    );
    expect(panel).toContain(
      "Verification checks only the frozen copied snapshot",
    );
    expect(panel).toContain(
      "independent of later live investigation changes.",
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
echo " SportsOS Milestone 6.86"
echo " Verification Result Snapshot Lock"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  stores all handoff fingerprint inputs with copied snapshot"
echo "  verification reconstructs only from frozen copied data"
echo "  later live trust/filter changes cannot affect verification"
echo "  clearer failed-verification wording"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
