#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.81.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-state"' "$PANEL" || {
  echo "Milestone 6.80 handoff gate is not present." >&2
  exit 1
}

grep -q 'const copyExportReceipt = useCallback' "$PANEL" || {
  echo "Export receipt copy callback is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.81-${STAMP}"

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

if (!text.includes('type HandoffReceiptCopyStatus = "IDLE" | "COPIED" | "ERROR";')) {
  const anchor = `type ExportHandoffState = "READY" | "BLOCKED";`;
  if (!text.includes(anchor)) {
    throw new Error("ExportHandoffState anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
type HandoffReceiptCopyStatus = "IDLE" | "COPIED" | "ERROR";`,
  );
}

if (!text.includes("const [handoffReceiptCopyStatus, setHandoffReceiptCopyStatus]")) {
  const anchor = `  const [exportReceiptCopyStatus, setExportReceiptCopyStatus] =
    useState<ExportReceiptCopyStatus>("IDLE");`;

  if (!text.includes(anchor)) {
    throw new Error("exportReceiptCopyStatus state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [handoffReceiptCopyStatus, setHandoffReceiptCopyStatus] =
    useState<HandoffReceiptCopyStatus>("IDLE");`,
  );
}

if (!text.includes("const copyHandoffReceipt = useCallback(")) {
  const anchor = `  const copyExportReceipt = useCallback(async () => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) {
    throw new Error("copyExportReceipt anchor not found");
  }

  const callback = `  const copyHandoffReceipt = useCallback(async () => {
    if (
      exportHandoffState !== "READY" ||
      !investigationExportReceipt
    ) {
      setHandoffReceiptCopyStatus("ERROR");
      return;
    }

    const trustTimeline = investigationTrustTimelineText({
      exportVerifiedAt: investigationExportReceipt.verifiedAt,
      currentVerifiedAt: lastTrustReverifiedAt,
      currentTrust: currentExportTrustSummary,
    });

    const recoveryLines = exportRecoveryReceiptLines({
      recoveryState: exportRecoveryState,
      linkCoherence: exportLinkCoherence,
      currentTrust: currentExportTrustSummary,
    });

    try {
      await copyPlainText(
        investigationExportReceiptText(
          investigationExportReceipt,
          trustTimeline,
          [
            ...recoveryLines,
            "Handoff gate: READY",
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
    exportLinkCoherence,
    exportRecoveryState,
    investigationExportReceipt,
    lastTrustReverifiedAt,
  ]);

`;

  text = text.slice(0, idx) + callback + text.slice(idx);
}

if (!text.includes('setHandoffReceiptCopyStatus("IDLE")')) {
  const anchor = `  useEffect(() => {
    if (exportReceiptCopyStatus === "IDLE") return;

    const timer = window.setTimeout(
      () => setExportReceiptCopyStatus("IDLE"),
      3_000,
    );

    return () => window.clearTimeout(timer);
  }, [exportReceiptCopyStatus]);`;

  if (!text.includes(anchor)) {
    throw new Error("export receipt copy timeout effect anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

  useEffect(() => {
    if (handoffReceiptCopyStatus === "IDLE") return;

    const timer = window.setTimeout(
      () => setHandoffReceiptCopyStatus("IDLE"),
      3_000,
    );

    return () => window.clearTimeout(timer);
  }, [handoffReceiptCopyStatus]);`,
  );
}

if (!text.includes('data-testid="director-audit-export-copy-handoff-receipt"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        investigationExportReceipt ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-copy-receipt"
            onClick={() => void copyExportReceipt()}
          >
            Copy export receipt
          </button>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Copy export receipt button anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        investigationExportReceipt ? (
          <button
            type="button"
            className="primary"
            data-testid="director-audit-export-copy-handoff-receipt"
            disabled={exportHandoffState !== "READY"}
            onClick={() => void copyHandoffReceipt()}
          >
            Copy handoff receipt
          </button>
        ) : null}

        {handoffReceiptCopyStatus !== "IDLE" ? (
          <span
            className="scheduleAuditHandoffReceiptCopyStatus"
            data-testid="director-audit-export-copy-handoff-receipt-status"
            role="status"
            aria-live="polite"
          >
            {handoffReceiptCopyStatus === "COPIED"
              ? "Handoff receipt copied."
              : "Handoff receipt is not ready to copy."}
          </span>
        ) : null}`,
  );
}

if (!text.includes('data-testid="director-audit-export-handoff-copy-requirement"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "BLOCKED" ? (
          <span
            className="scheduleAuditExportHandoffWarning"
            data-testid="director-audit-export-handoff-warning"
            role="status"
            aria-live="polite"
          >
            Receipt copy is available for historical review, but this export is
            not handoff-ready until recovery reaches READY.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff warning UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "BLOCKED" ? (
          <span
            className="scheduleAuditExportHandoffCopyRequirement"
            data-testid="director-audit-export-handoff-copy-requirement"
          >
            The handoff receipt copy action unlocks after the handoff gate
            reaches READY.
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

describe("Tournament scheduling 6.81 dedicated handoff receipt copy", () => {
  it("models handoff receipt copy state explicitly", () => {
    expect(panel).toContain(
      'type HandoffReceiptCopyStatus = "IDLE" | "COPIED" | "ERROR"',
    );
    expect(panel).toContain(
      "const [handoffReceiptCopyStatus, setHandoffReceiptCopyStatus]",
    );
  });

  it("requires the handoff gate to be READY before copying", () => {
    expect(panel).toContain(
      'exportHandoffState !== "READY"',
    );
    expect(panel).toContain(
      "const copyHandoffReceipt = useCallback",
    );
  });

  it("adds the READY gate marker to the handoff receipt", () => {
    expect(panel).toContain(
      '"Handoff gate: READY"',
    );
  });

  it("keeps historical export receipt copy available separately", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-receipt"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-handoff-receipt"',
    );
  });

  it("disables handoff copy until the gate is ready", () => {
    expect(panel).toContain(
      'disabled={exportHandoffState !== "READY"}',
    );
    expect(panel).toContain(
      "Copy handoff receipt",
    );
  });

  it("provides accessible copy feedback", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-handoff-receipt-status"',
    );
    expect(panel).toContain("Handoff receipt copied.");
    expect(panel).toContain(
      "Handoff receipt is not ready to copy.",
    );
    expect(panel).toContain('aria-live="polite"');
  });

  it("explains the unlock requirement while blocked", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copy-requirement"',
    );
    expect(panel).toContain(
      "unlocks after the handoff gate",
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
echo " SportsOS Milestone 6.81"
echo " Dedicated Handoff Receipt Copy"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  historical receipt copy remains available"
echo "  dedicated handoff receipt copy added"
echo "  handoff copy disabled until gate is READY"
echo "  handoff receipt includes explicit READY marker"
echo "  accessible success/error feedback"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
