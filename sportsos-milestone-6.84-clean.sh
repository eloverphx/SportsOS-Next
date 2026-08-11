#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.84.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-handoff-snapshot-freeze"' "$PANEL" || {
  echo "Milestone 6.83 handoff snapshot freeze is not present." >&2
  exit 1
}

grep -q 'const handoffFingerprint = handoffReceiptFingerprint(snapshot)' "$PANEL" || {
  echo "Milestone 6.83 frozen handoff fingerprint path is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.84-${STAMP}"

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

if (!text.includes("type CopiedHandoffSnapshot = {")) {
  const anchor = `type HandoffReceiptSnapshot = {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("HandoffReceiptSnapshot anchor not found");

  const typeBlock = `type CopiedHandoffSnapshot = {
  readonly fingerprint: string;
  readonly capturedAt: string;
  readonly shareUrl: string;
};

`;

  text = text.slice(0, idx) + typeBlock + text.slice(idx);
}

if (!text.includes("const [copiedHandoffSnapshot, setCopiedHandoffSnapshot]")) {
  const anchor = `  const [handoffReceiptCopyStatus, setHandoffReceiptCopyStatus] =
    useState<HandoffReceiptCopyStatus>("IDLE");`;

  if (!text.includes(anchor)) {
    throw new Error("handoffReceiptCopyStatus state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [copiedHandoffSnapshot, setCopiedHandoffSnapshot] =
    useState<CopiedHandoffSnapshot | null>(null);`,
  );
}

const successAnchor = `      setHandoffReceiptCopyStatus("COPIED");`;

if (!text.includes("setCopiedHandoffSnapshot({")) {
  if (!text.includes(successAnchor)) {
    throw new Error("Handoff copy success anchor not found");
  }

  text = text.replace(
    successAnchor,
    `      setCopiedHandoffSnapshot({
        fingerprint: handoffFingerprint,
        capturedAt: snapshot.capturedAt,
        shareUrl: snapshot.shareUrl,
      });
      setHandoffReceiptCopyStatus("COPIED");`,
  );
}

if (!text.includes("setCopiedHandoffSnapshot(null);")) {
  const failAnchor = `      setHandoffReceiptCopyStatus("ERROR");`;
  const first = text.indexOf(failAnchor);
  if (first < 0) throw new Error("Handoff copy error anchor not found");

  text = text.slice(0, first) +
    `      setCopiedHandoffSnapshot(null);
${failAnchor}` +
    text.slice(first + failAnchor.length);
}

if (!text.includes('data-testid="director-audit-export-handoff-copied-snapshot"')) {
  const anchor = `        {handoffReceiptCopyStatus !== "IDLE" ? (
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
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Handoff receipt copy status UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {handoffReceiptCopyStatus === "COPIED" &&
        copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditCopiedHandoffSnapshot"
            data-testid="director-audit-export-handoff-copied-snapshot"
          >
            Copied snapshot{" "}
            <code>{copiedHandoffSnapshot.fingerprint}</code>{" "}
            captured {formatWhen(copiedHandoffSnapshot.capturedAt)}
          </span>
        ) : null}

        {handoffReceiptCopyStatus === "COPIED" &&
        copiedHandoffSnapshot ? (
          <span
            className="scheduleAuditCopiedHandoffSnapshotUrl"
            data-testid="director-audit-export-handoff-copied-snapshot-url"
          >
            Snapshot URL{" "}
            <code>{copiedHandoffSnapshot.shareUrl}</code>
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

describe("Tournament scheduling 6.84 handoff snapshot confirmation", () => {
  it("models the exact copied handoff snapshot identity", () => {
    expect(panel).toContain("type CopiedHandoffSnapshot = {");
    expect(panel).toContain("readonly fingerprint: string");
    expect(panel).toContain("readonly capturedAt: string");
    expect(panel).toContain("readonly shareUrl: string");
  });

  it("stores the frozen fingerprint and capture time only after copy succeeds", () => {
    expect(panel).toContain(
      "const [copiedHandoffSnapshot, setCopiedHandoffSnapshot]",
    );
    expect(panel).toContain("setCopiedHandoffSnapshot({");
    expect(panel).toContain("fingerprint: handoffFingerprint");
    expect(panel).toContain("capturedAt: snapshot.capturedAt");
    expect(panel).toContain("shareUrl: snapshot.shareUrl");
  });

  it("clears copied snapshot state on handoff copy failure", () => {
    expect(panel).toContain("setCopiedHandoffSnapshot(null)");
    expect(panel).toContain(
      'setHandoffReceiptCopyStatus("ERROR")',
    );
  });

  it("renders the exact copied handoff fingerprint and capture time", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copied-snapshot"',
    );
    expect(panel).toContain(
      "<code>{copiedHandoffSnapshot.fingerprint}</code>",
    );
    expect(panel).toContain(
      "formatWhen(copiedHandoffSnapshot.capturedAt)",
    );
  });

  it("renders the exact exported URL bound into the copied snapshot", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copied-snapshot-url"',
    );
    expect(panel).toContain(
      "<code>{copiedHandoffSnapshot.shareUrl}</code>",
    );
  });

  it("preserves frozen handoff receipt creation", () => {
    expect(panel).toContain(
      "const snapshot = createHandoffReceiptSnapshot({",
    );
    expect(panel).toContain(
      "const handoffFingerprint = handoffReceiptFingerprint(snapshot)",
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
echo " SportsOS Milestone 6.84"
echo " Handoff Snapshot Confirmation"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  stores exact copied handoff fingerprint after successful copy"
echo "  stores exact snapshot capture timestamp"
echo "  stores exact canonical URL bound into snapshot"
echo "  clears copied snapshot identity on failure"
echo "  operator can confirm the immutable bundle actually copied"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
