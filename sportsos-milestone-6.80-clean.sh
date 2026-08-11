#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.80.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-recovery-receipt"' "$PANEL" || {
  echo "Milestone 6.79 recovery receipt metadata is not present." >&2
  exit 1
}

grep -q 'const copyExportReceipt = useCallback' "$PANEL" || {
  echo "Export receipt copy callback is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.80-${STAMP}"

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

if (!text.includes('type ExportHandoffState = "READY" | "BLOCKED";')) {
  const anchor = `type ExportRecoveryState = "READY" | "NEEDS_ACTION";`;
  if (!text.includes(anchor)) {
    throw new Error("ExportRecoveryState anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
type ExportHandoffState = "READY" | "BLOCKED";`,
  );
}

if (!text.includes("const exportHandoffState = useMemo<ExportHandoffState | null>(")) {
  const anchor = `  const exportRecoveryState = useMemo<ExportRecoveryState | null>(() => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("exportRecoveryState memo anchor not found");

  const end = text.indexOf("\n\n", idx);
  if (end < 0) throw new Error("exportRecoveryState memo block end not found");

  const memo = `

  const exportHandoffState = useMemo<ExportHandoffState | null>(() => {
    if (!exportRecoveryState) return null;

    return exportRecoveryState === "READY" ? "READY" : "BLOCKED";
  }, [exportRecoveryState]);`;

  text = text.slice(0, end) + memo + text.slice(end);
}

if (!text.includes('data-testid="director-audit-export-handoff-state"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        exportRecoveryState ? (
          <span
            className="scheduleAuditExportRecoveryReceipt"
            data-testid="director-audit-export-recovery-receipt"
          >
            Copied export receipts include recovery state, exported-link
            coherence, and current trust at handoff.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Recovery receipt UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState ? (
          <span
            className={\`scheduleAuditExportHandoffState \${exportHandoffState.toLowerCase()}\`}
            data-testid="director-audit-export-handoff-state"
          >
            {exportHandoffState === "READY"
              ? "Handoff ready: exported scope matches and current trust is verified."
              : "Handoff blocked: restore and verify the exported investigation before sharing the receipt."}
          </span>
        ) : null}`,
  );
}

if (!text.includes('data-testid="director-audit-export-handoff-warning"')) {
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
        ) : null}`,
  );
}

if (!text.includes('data-testid="director-audit-export-handoff-ready"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState ? (
          <span
            className={\`scheduleAuditExportHandoffState \${exportHandoffState.toLowerCase()}\`}
            data-testid="director-audit-export-handoff-state"
          >
            {exportHandoffState === "READY"
              ? "Handoff ready: exported scope matches and current trust is verified."
              : "Handoff blocked: restore and verify the exported investigation before sharing the receipt."}
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff state UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" ? (
          <span
            className="scheduleAuditExportHandoffReady"
            data-testid="director-audit-export-handoff-ready"
            role="status"
            aria-live="polite"
          >
            Handoff gate passed.
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

describe("Tournament scheduling 6.80 recovery handoff gate", () => {
  it("models export handoff state explicitly", () => {
    expect(panel).toContain(
      'type ExportHandoffState = "READY" | "BLOCKED"',
    );
  });

  it("derives handoff readiness from unified recovery state", () => {
    expect(panel).toContain(
      "const exportHandoffState = useMemo<ExportHandoffState | null>",
    );
    expect(panel).toContain(
      'exportRecoveryState === "READY" ? "READY" : "BLOCKED"',
    );
  });

  it("renders a clear handoff state", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-state"',
    );
    expect(panel).toContain(
      "Handoff ready: exported scope matches and current trust is verified.",
    );
    expect(panel).toContain(
      "Handoff blocked: restore and verify the exported investigation",
    );
  });

  it("warns when a copied receipt is not handoff-ready", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-warning"',
    );
    expect(panel).toContain(
      "Receipt copy is available for historical review",
    );
    expect(panel).toContain(
      "not handoff-ready until recovery reaches READY",
    );
  });

  it("shows a final passed gate when recovery is ready", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-ready"',
    );
    expect(panel).toContain("Handoff gate passed.");
    expect(panel).toContain('aria-live="polite"');
  });

  it("preserves receipt copy for historical review", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-receipt"',
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
echo " SportsOS Milestone 6.80"
echo " Recovery Handoff Gate"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  derives handoff readiness from unified recovery state"
echo "  READY only when exported scope matches and trust is verified"
echo "  BLOCKED state warns before operational handoff"
echo "  historical receipt copy remains available"
echo "  explicit final handoff gate confirmation"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
