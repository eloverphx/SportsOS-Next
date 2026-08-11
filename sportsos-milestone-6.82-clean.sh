#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.82.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-copy-handoff-receipt"' "$PANEL" || {
  echo "Milestone 6.81 dedicated handoff receipt copy is not present." >&2
  exit 1
}

grep -q 'Handoff gate: READY' "$PANEL" || {
  echo "Milestone 6.81 handoff READY marker is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.82-${STAMP}"

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

if (!text.includes("function handoffReceiptFingerprint(")) {
  const anchor = "function auditEvidenceFingerprint(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("auditEvidenceFingerprint anchor not found");

  const helper = `function handoffReceiptFingerprint(input: {
  readonly evidenceFingerprint: string;
  readonly shareUrl: string;
  readonly recoveryState: ExportRecoveryState;
  readonly handoffState: ExportHandoffState;
  readonly currentTrust: ExportTrustSummary;
  readonly verifiedAt: string | null;
  readonly lastTrustReverifiedAt: string | null;
}): string {
  const canonical = [
    input.evidenceFingerprint,
    input.shareUrl,
    input.recoveryState,
    input.handoffState,
    input.currentTrust,
    input.verifiedAt ?? "",
    input.lastTrustReverifiedAt ?? "",
  ].join("|");

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

if (!text.includes("const currentHandoffReceiptFingerprint = useMemo(")) {
  const anchor = `  const exportHandoffState = useMemo<ExportHandoffState | null>(() => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("exportHandoffState memo anchor not found");

  const end = text.indexOf("\n\n", idx);
  if (end < 0) throw new Error("exportHandoffState memo block end not found");

  const memo = `

  const currentHandoffReceiptFingerprint = useMemo(() => {
    if (
      !investigationExportReceipt ||
      !exportRecoveryState ||
      !exportHandoffState ||
      !currentExportTrustSummary
    ) {
      return null;
    }

    return handoffReceiptFingerprint({
      evidenceFingerprint: investigationExportReceipt.evidenceFingerprint,
      shareUrl: investigationExportReceipt.shareUrl,
      recoveryState: exportRecoveryState,
      handoffState: exportHandoffState,
      currentTrust: currentExportTrustSummary,
      verifiedAt: investigationExportReceipt.verifiedAt,
      lastTrustReverifiedAt,
    });
  }, [
    currentExportTrustSummary,
    exportHandoffState,
    exportRecoveryState,
    investigationExportReceipt,
    lastTrustReverifiedAt,
  ]);`;

  text = text.slice(0, end) + memo + text.slice(end);
}

const oldGateMarker = `            ...recoveryLines,
            "Handoff gate: READY",
          ],`;

if (text.includes(oldGateMarker)) {
  text = text.replace(
    oldGateMarker,
    `            ...recoveryLines,
            "Handoff gate: READY",
            \`Handoff fingerprint: \${currentHandoffReceiptFingerprint ?? "unavailable"}\`,
          ],`,
  );
} else if (!text.includes("Handoff fingerprint: ${currentHandoffReceiptFingerprint")) {
  throw new Error("Handoff receipt READY marker block not found");
}

const depAnchor = `    currentExportTrustSummary,
    exportHandoffState,
    exportLinkCoherence,`;

if (text.includes(depAnchor) && !text.includes("currentHandoffReceiptFingerprint,\n    currentExportTrustSummary")) {
  text = text.replace(
    depAnchor,
    `    currentExportTrustSummary,
    currentHandoffReceiptFingerprint,
    exportHandoffState,
    exportLinkCoherence,`,
  );
}

if (!text.includes('data-testid="director-audit-export-handoff-fingerprint"')) {
  const anchor = `        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" ? (
          <span
            className="scheduleAuditExportHandoffReady"
            data-testid="director-audit-export-handoff-ready"
            role="status"
            aria-live="polite"
          >
            Handoff gate passed.
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff ready UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {investigationExportStatus === "EXPORTED" &&
        exportHandoffState === "READY" &&
        currentHandoffReceiptFingerprint ? (
          <span
            className="scheduleAuditExportHandoffFingerprint"
            data-testid="director-audit-export-handoff-fingerprint"
          >
            Handoff fingerprint{" "}
            <code>{currentHandoffReceiptFingerprint}</code>
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

describe("Tournament scheduling 6.82 handoff receipt integrity stamp", () => {
  it("defines a deterministic handoff receipt fingerprint", () => {
    expect(panel).toContain(
      "function handoffReceiptFingerprint(",
    );
    expect(panel).toContain(
      "input.evidenceFingerprint",
    );
    expect(panel).toContain(
      "input.shareUrl",
    );
    expect(panel).toContain(
      "input.recoveryState",
    );
    expect(panel).toContain(
      "input.handoffState",
    );
    expect(panel).toContain(
      "input.currentTrust",
    );
    expect(panel).toContain(
      "Math.imul(hash, 16777619)",
    );
  });

  it("derives the current handoff fingerprint from live trusted state", () => {
    expect(panel).toContain(
      "const currentHandoffReceiptFingerprint = useMemo",
    );
    expect(panel).toContain(
      "evidenceFingerprint: investigationExportReceipt.evidenceFingerprint",
    );
    expect(panel).toContain(
      "shareUrl: investigationExportReceipt.shareUrl",
    );
    expect(panel).toContain(
      "handoffState: exportHandoffState",
    );
    expect(panel).toContain(
      "currentTrust: currentExportTrustSummary",
    );
  });

  it("includes the integrity stamp in the handoff receipt", () => {
    expect(panel).toContain(
      "Handoff fingerprint: ${currentHandoffReceiptFingerprint ?? \"unavailable\"}",
    );
  });

  it("renders the handoff fingerprint when the gate is ready", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-fingerprint"',
    );
    expect(panel).toContain(
      "<code>{currentHandoffReceiptFingerprint}</code>",
    );
  });

  it("preserves the dedicated handoff copy gate", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-handoff-receipt"',
    );
    expect(panel).toContain(
      'disabled={exportHandoffState !== "READY"}',
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
echo " SportsOS Milestone 6.82"
echo " Handoff Receipt Integrity Stamp"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  deterministic handoff fingerprint added"
echo "  fingerprint binds evidence + URL + recovery + trust"
echo "  fingerprint included in READY handoff receipt"
echo "  operator-visible handoff fingerprint shown"
echo "  dedicated handoff gate preserved"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
