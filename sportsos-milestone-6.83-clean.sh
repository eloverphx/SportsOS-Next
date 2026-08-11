#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.83.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'function handoffReceiptFingerprint(' "$PANEL" || {
  echo "Milestone 6.82 handoff fingerprint helper is not present." >&2
  exit 1
}

grep -q 'const copyHandoffReceipt = useCallback' "$PANEL" || {
  echo "Dedicated handoff receipt copy callback is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.83-${STAMP}"

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

if (!text.includes("type HandoffReceiptSnapshot = {")) {
  const anchor = `type InvestigationExportReceipt = {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("InvestigationExportReceipt type anchor not found");

  const helperType = `type HandoffReceiptSnapshot = {
  readonly evidenceFingerprint: string;
  readonly shareUrl: string;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly exportVerifiedAt: string | null;
  readonly lastTrustReverifiedAt: string | null;
  readonly capturedAt: string;
};

`;

  text = text.slice(0, idx) + helperType + text.slice(idx);
}

if (!text.includes("function createHandoffReceiptSnapshot(")) {
  const anchor = "function handoffReceiptFingerprint(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("handoffReceiptFingerprint anchor not found");

  const helper = `function createHandoffReceiptSnapshot(input: {
  readonly receipt: InvestigationExportReceipt;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly lastTrustReverifiedAt: string | null;
}): HandoffReceiptSnapshot {
  return {
    evidenceFingerprint: input.receipt.evidenceFingerprint,
    shareUrl: input.receipt.shareUrl,
    recoveryState: input.recoveryState,
    handoffState: input.handoffState,
    currentTrust: input.currentTrust,
    exportVerifiedAt: input.receipt.verifiedAt,
    lastTrustReverifiedAt: input.lastTrustReverifiedAt,
    capturedAt: new Date().toISOString(),
  };
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

const oldFingerprintSig = `function handoffReceiptFingerprint(input: {
  readonly evidenceFingerprint: string;
  readonly shareUrl: string;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly verifiedAt: string | null;
  readonly lastTrustReverifiedAt: string | null;
}): string {`;

if (text.includes(oldFingerprintSig)) {
  text = text.replace(
    oldFingerprintSig,
    `function handoffReceiptFingerprint(
  input: HandoffReceiptSnapshot,
): string {`,
  );
  text = text.replace(
    `    input.verifiedAt ?? "",`,
    `    input.exportVerifiedAt ?? "",`,
  );
  text = text.replace(
    `    input.lastTrustReverifiedAt ?? "",
  ].join("|");`,
    `    input.lastTrustReverifiedAt ?? "",
    input.capturedAt,
  ].join("|");`,
  );
}

const memoStart = `  const currentHandoffReceiptFingerprint = useMemo(() => {`;
const memoIdx = text.indexOf(memoStart);
if (memoIdx >= 0) {
  const memoEnd = text.indexOf("\n\n", memoIdx);
  if (memoEnd < 0) throw new Error("currentHandoffReceiptFingerprint memo end not found");
  text = text.slice(0, memoIdx) + text.slice(memoEnd + 2);
}

const copyStart = `  const copyHandoffReceipt = useCallback(async () => {`;
const copyIdx = text.indexOf(copyStart);
if (copyIdx < 0) throw new Error("copyHandoffReceipt callback not found");

const copyEndMarker = `  const copyExportReceipt = useCallback(async () => {`;
const copyEnd = text.indexOf(copyEndMarker, copyIdx);
if (copyEnd < 0) throw new Error("copyHandoffReceipt end anchor not found");

const replacement = `  const copyHandoffReceipt = useCallback(async () => {
    if (
      exportHandoffState !== "READY" ||
      exportRecoveryState !== "READY" ||
      currentExportTrustSummary !== "VERIFIED" ||
      !investigationExportReceipt
    ) {
      setHandoffReceiptCopyStatus("ERROR");
      return;
    }

    const snapshot = createHandoffReceiptSnapshot({
      receipt: investigationExportReceipt,
      recoveryState: exportRecoveryState,
      handoffState: exportHandoffState,
      currentTrust: currentExportTrustSummary,
      lastTrustReverifiedAt,
    });

    const handoffFingerprint = handoffReceiptFingerprint(snapshot);

    const trustTimeline = investigationTrustTimelineText({
      exportVerifiedAt: snapshot.exportVerifiedAt,
      currentVerifiedAt: snapshot.lastTrustReverifiedAt,
      currentTrust: snapshot.currentTrust,
    });

    const recoveryLines = exportRecoveryReceiptLines({
      recoveryState: snapshot.recoveryState,
      linkCoherence: "MATCHES",
      currentTrust: snapshot.currentTrust,
    });

    try {
      await copyPlainText(
        investigationExportReceiptText(
          investigationExportReceipt,
          trustTimeline,
          [
            ...recoveryLines,
            "Handoff gate: READY",
            \`Handoff snapshot captured: \${snapshot.capturedAt}\`,
            \`Handoff fingerprint: \${handoffFingerprint}\`,
          ],
        ),
      );
      setHandoffReceiptCopyStatus("COPIED");
    } catch {
      setHandoffReceiptCopyStatus("ERROR");
    }
  }, [
    currentExportTrustSummary,
    exportHandoffState,
    exportRecoveryState,
    investigationExportReceipt,
    lastTrustReverifiedAt,
  ]);

`;

text = text.slice(0, copyIdx) + replacement + text.slice(copyEnd);

if (text.includes("currentHandoffReceiptFingerprint")) {
  const uiBlock = `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" &&
        currentHandoffReceiptFingerprint ? (
          <span
            className="scheduleAuditExportHandoffFingerprint"
            data-testid="director-audit-export-handoff-fingerprint"
          >
            Handoff fingerprint{" "}
            <code>{currentHandoffReceiptFingerprint}</code>
          </span>
        ) : null}`;

  if (text.includes(uiBlock)) {
    text = text.replace(
      uiBlock,
      `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" ? (
          <span
            className="scheduleAuditExportHandoffFingerprint"
            data-testid="director-audit-export-handoff-fingerprint"
          >
            Handoff fingerprint is generated from a frozen READY snapshot when
            the handoff receipt is copied.
          </span>
        ) : null}`,
    );
  }
}

if (!text.includes('data-testid="director-audit-export-handoff-snapshot-freeze"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" ? (
          <span
            className="scheduleAuditExportHandoffFingerprint"
            data-testid="director-audit-export-handoff-fingerprint"
          >
            Handoff fingerprint is generated from a frozen READY snapshot when
            the handoff receipt is copied.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff fingerprint UI anchor not found after rewrite");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" ? (
          <span
            className="scheduleAuditExportHandoffSnapshotFreeze"
            data-testid="director-audit-export-handoff-snapshot-freeze"
          >
            Receipt contents and fingerprint are generated from the same frozen
            handoff snapshot.
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

describe("Tournament scheduling 6.83 handoff snapshot freeze", () => {
  it("models an immutable handoff receipt snapshot", () => {
    expect(panel).toContain("type HandoffReceiptSnapshot = {");
    expect(panel).toContain("readonly evidenceFingerprint: string");
    expect(panel).toContain("readonly shareUrl: string");
    expect(panel).toContain("readonly recoveryState: ExportRecoveryState");
    expect(panel).toContain("readonly handoffState: ExportHandoffState");
    expect(panel).toContain("readonly currentTrust: ExportTrustSummary");
    expect(panel).toContain("readonly capturedAt: string");
  });

  it("creates one frozen snapshot before fingerprinting and copying", () => {
    expect(panel).toContain("function createHandoffReceiptSnapshot(");
    expect(panel).toContain(
      "const snapshot = createHandoffReceiptSnapshot({",
    );
    expect(panel).toContain(
      "const handoffFingerprint = handoffReceiptFingerprint(snapshot)",
    );
  });

  it("requires READY recovery and VERIFIED trust at copy time", () => {
    expect(panel).toContain(
      'exportHandoffState !== "READY"',
    );
    expect(panel).toContain(
      'exportRecoveryState !== "READY"',
    );
    expect(panel).toContain(
      'currentExportTrustSummary !== "VERIFIED"',
    );
  });

  it("derives receipt timeline from the same frozen snapshot", () => {
    expect(panel).toContain(
      "exportVerifiedAt: snapshot.exportVerifiedAt",
    );
    expect(panel).toContain(
      "currentVerifiedAt: snapshot.lastTrustReverifiedAt",
    );
    expect(panel).toContain(
      "currentTrust: snapshot.currentTrust",
    );
  });

  it("stamps the snapshot capture time into the handoff receipt", () => {
    expect(panel).toContain(
      "Handoff snapshot captured: ${snapshot.capturedAt}",
    );
    expect(panel).toContain(
      "Handoff fingerprint: ${handoffFingerprint}",
    );
  });

  it("explains snapshot freezing to the operator", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-snapshot-freeze"',
    );
    expect(panel).toContain(
      "Receipt contents and fingerprint are generated from the same frozen",
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
echo " SportsOS Milestone 6.83"
echo " Handoff Snapshot Freeze"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  freezes one immutable READY handoff snapshot at copy time"
echo "  receipt contents derive from that snapshot"
echo "  fingerprint derives from that same snapshot"
echo "  snapshot capture timestamp is stamped into receipt"
echo "  READY + VERIFIED conditions rechecked at copy time"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
