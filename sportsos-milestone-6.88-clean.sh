#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.88.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-copy-verification-record"' "$PANEL" || {
  echo "Milestone 6.87 verification record copy action is not present." >&2
  exit 1
}

grep -q 'function copiedHandoffVerificationLines(' "$PANEL" || {
  echo "Verification record formatter is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.88-${STAMP}"

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

if (!text.includes("Handoff fingerprint: ${snapshot.fingerprint}")) {
  const anchor = `  return [
    \`Snapshot verification: \${snapshot.verificationStatus}\`,
    \`Snapshot verified at: \${snapshot.verifiedAt ?? "not verified"}\`,
  ];`;

  if (!text.includes(anchor)) {
    throw new Error("copiedHandoffVerificationLines body anchor not found");
  }

  text = text.replace(
    anchor,
    `  return [
    \`Handoff fingerprint: \${snapshot.fingerprint}\`,
    \`Snapshot verification: \${snapshot.verificationStatus}\`,
    \`Snapshot verified at: \${snapshot.verifiedAt ?? "not verified"}\`,
    \`Snapshot captured at: \${snapshot.capturedAt}\`,
    \`Snapshot URL: \${snapshot.shareUrl}\`,
  ];`,
  );
}

if (!text.includes("function verificationRecordFingerprint(")) {
  const anchor = "function copiedHandoffVerificationLines(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("copiedHandoffVerificationLines anchor not found");

  const helper = `function verificationRecordFingerprint(
  snapshot: CopiedHandoffSnapshot,
): string {
  const canonical = copiedHandoffVerificationLines(snapshot).join("|");
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

if (!text.includes("Verification record fingerprint:")) {
  const anchor = `                copiedHandoffVerificationLines(
                  copiedHandoffSnapshot,
                ).join("\\n"),`;

  if (!text.includes(anchor)) {
    throw new Error("Copy verification record formatter call anchor not found");
  }

  text = text.replace(
    anchor,
    `                [
                  ...copiedHandoffVerificationLines(
                    copiedHandoffSnapshot,
                  ),
                  \`Verification record fingerprint: \${verificationRecordFingerprint(
                    copiedHandoffSnapshot,
                  )}\`,
                ].join("\\n"),`,
  );
}

if (!text.includes('data-testid="director-audit-export-verification-record-fingerprint"')) {
  const anchor = `        {copiedHandoffSnapshot ? (
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
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Verification receipt UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {copiedHandoffSnapshot &&
        copiedHandoffSnapshot.verificationStatus !== "IDLE" ? (
          <span
            className="scheduleAuditVerificationRecordFingerprint"
            data-testid="director-audit-export-verification-record-fingerprint"
          >
            Verification record fingerprint{" "}
            <code>{verificationRecordFingerprint(copiedHandoffSnapshot)}</code>
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

describe("Tournament scheduling 6.88 verification record integrity binding", () => {
  it("binds the verification record to the handoff fingerprint", () => {
    expect(panel).toContain(
      "Handoff fingerprint: ${snapshot.fingerprint}",
    );
    expect(panel).toContain(
      "Snapshot captured at: ${snapshot.capturedAt}",
    );
    expect(panel).toContain(
      "Snapshot URL: ${snapshot.shareUrl}",
    );
  });

  it("defines a deterministic fingerprint for the verification record", () => {
    expect(panel).toContain(
      "function verificationRecordFingerprint(",
    );
    expect(panel).toContain(
      "copiedHandoffVerificationLines(snapshot).join(\"|\")",
    );
    expect(panel).toContain(
      "Math.imul(hash, 16777619)",
    );
  });

  it("adds the verification record fingerprint to copied verification notes", () => {
    expect(panel).toContain(
      "Verification record fingerprint: ${verificationRecordFingerprint(",
    );
  });

  it("renders the verification record fingerprint in the UI", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-verification-record-fingerprint"',
    );
    expect(panel).toContain(
      "<code>{verificationRecordFingerprint(copiedHandoffSnapshot)}</code>",
    );
  });

  it("preserves the dedicated verification record copy action", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-verification-record"',
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
echo " SportsOS Milestone 6.88"
echo " Verification Record Integrity Binding"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  verification record includes handoff fingerprint"
echo "  includes snapshot capture time and canonical URL"
echo "  deterministic verification-record fingerprint added"
echo "  copied verification notes include integrity fingerprint"
echo "  operator-visible verification-record fingerprint"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
