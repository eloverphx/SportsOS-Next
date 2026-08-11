#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.85.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-copied-snapshot"' "$PANEL" || {
  echo "Milestone 6.84 copied handoff snapshot confirmation is not present." >&2
  exit 1
}

grep -q 'function handoffReceiptFingerprint(' "$PANEL" || {
  echo "Handoff fingerprint helper is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.85-${STAMP}"

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

if (!text.includes('type HandoffSnapshotVerification = "IDLE" | "VERIFIED" | "FAILED";')) {
  const anchor = `type HandoffReceiptCopyStatus = "IDLE" | "COPIED" | "ERROR";`;
  if (!text.includes(anchor)) {
    throw new Error("HandoffReceiptCopyStatus anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
type HandoffSnapshotVerification = "IDLE" | "VERIFIED" | "FAILED";`,
  );
}

if (!text.includes("const [handoffSnapshotVerification, setHandoffSnapshotVerification]")) {
  const anchor = `  const [copiedHandoffSnapshot, setCopiedHandoffSnapshot] =
    useState<CopiedHandoffSnapshot | null>(null);`;

  if (!text.includes(anchor)) {
    throw new Error("copiedHandoffSnapshot state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [handoffSnapshotVerification, setHandoffSnapshotVerification] =
    useState<HandoffSnapshotVerification>("IDLE");`,
  );
}

if (!text.includes("const verifyCopiedHandoffSnapshot = useCallback(")) {
  const anchor = `  const copyHandoffReceipt = useCallback(async () => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("copyHandoffReceipt anchor not found");

  const callback = `  const verifyCopiedHandoffSnapshot = useCallback(() => {
    if (
      !copiedHandoffSnapshot ||
      !investigationExportReceipt ||
      !exportRecoveryState ||
      !exportHandoffState ||
      !currentExportTrustSummary
    ) {
      setHandoffSnapshotVerification("FAILED");
      return;
    }

    const verificationSnapshot: HandoffReceiptSnapshot = {
      evidenceFingerprint: investigationExportReceipt.evidenceFingerprint,
      shareUrl: copiedHandoffSnapshot.shareUrl,
      recoveryState: exportRecoveryState,
      handoffState: exportHandoffState,
      currentTrust: currentExportTrustSummary,
      exportVerifiedAt: investigationExportReceipt.verifiedAt,
      lastTrustReverifiedAt,
      capturedAt: copiedHandoffSnapshot.capturedAt,
    };

    const recalculated = handoffReceiptFingerprint(verificationSnapshot);

    setHandoffSnapshotVerification(
      recalculated === copiedHandoffSnapshot.fingerprint
        ? "VERIFIED"
        : "FAILED",
    );
  }, [
    copiedHandoffSnapshot,
    currentExportTrustSummary,
    exportHandoffState,
    exportRecoveryState,
    investigationExportReceipt,
    lastTrustReverifiedAt,
  ]);

`;

  text = text.slice(0, idx) + callback + text.slice(idx);
}

if (!text.includes('setHandoffSnapshotVerification("IDLE")')) {
  const anchor = `  useEffect(() => {
    if (handoffReceiptCopyStatus === "IDLE") return;

    const timer = window.setTimeout(
      () => setHandoffReceiptCopyStatus("IDLE"),
      3_000,
    );

    return () => window.clearTimeout(timer);
  }, [handoffReceiptCopyStatus]);`;

  if (!text.includes(anchor)) {
    throw new Error("handoff receipt copy timeout effect anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

  useEffect(() => {
    if (handoffSnapshotVerification === "IDLE") return;

    const timer = window.setTimeout(
      () => setHandoffSnapshotVerification("IDLE"),
      5_000,
    );

    return () => window.clearTimeout(timer);
  }, [handoffSnapshotVerification]);`,
  );
}

if (!text.includes('data-testid="director-audit-export-handoff-verify-snapshot"')) {
  const anchor = `        {handoffReceiptCopyStatus === "COPIED" &&
        copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditCopiedHandoffSnapshotUrl"
            data-testid="director-audit-export-handoff-copied-snapshot-url"
          >
            Snapshot URL{" "}
            <code>{copiedHandoffSnapshot.shareUrl}</code>
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Copied handoff snapshot URL UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {handoffReceiptCopyStatus === "COPIED" &&
        copiedHandoffSnapshot ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-handoff-verify-snapshot"
            onClick={verifyCopiedHandoffSnapshot}
          >
            Verify copied handoff snapshot
          </button>
        ) : null}

        {handoffSnapshotVerification !== "IDLE" ? (
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

describe("Tournament scheduling 6.85 handoff receipt verification check", () => {
  it("models copied snapshot verification status", () => {
    expect(panel).toContain(
      'type HandoffSnapshotVerification = "IDLE" | "VERIFIED" | "FAILED"',
    );
    expect(panel).toContain(
      "const [handoffSnapshotVerification, setHandoffSnapshotVerification]",
    );
  });

  it("rebuilds verification inputs using the copied snapshot capture time and URL", () => {
    expect(panel).toContain(
      "const verificationSnapshot: HandoffReceiptSnapshot = {",
    );
    expect(panel).toContain(
      "shareUrl: copiedHandoffSnapshot.shareUrl",
    );
    expect(panel).toContain(
      "capturedAt: copiedHandoffSnapshot.capturedAt",
    );
  });

  it("recalculates the handoff fingerprint and compares it to the copied identity", () => {
    expect(panel).toContain(
      "const recalculated = handoffReceiptFingerprint(verificationSnapshot)",
    );
    expect(panel).toContain(
      "recalculated === copiedHandoffSnapshot.fingerprint",
    );
  });

  it("renders a local copied-snapshot verification action", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verify-snapshot"',
    );
    expect(panel).toContain(
      "Verify copied handoff snapshot",
    );
  });

  it("provides accessible verification result feedback", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-verify-snapshot-status"',
    );
    expect(panel).toContain(
      "Copied handoff snapshot fingerprint verified.",
    );
    expect(panel).toContain(
      "Copied handoff snapshot fingerprint does not match current verification inputs.",
    );
    expect(panel).toContain('aria-live="polite"');
  });

  it("preserves copied handoff snapshot identity display", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copied-snapshot"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copied-snapshot-url"',
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
echo " SportsOS Milestone 6.85"
echo " Handoff Receipt Verification Check"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  adds local verification for copied handoff snapshot"
echo "  recomputes fingerprint from stored snapshot identity"
echo "  compares against copied fingerprint"
echo "  provides accessible verified/failed feedback"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
