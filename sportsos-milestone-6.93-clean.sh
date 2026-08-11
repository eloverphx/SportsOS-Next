#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
TEST="apps/api/test/tournament-schedule-6.93.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-frozen-verification-bundle"' "$PANEL" || {
  echo "Milestone 6.92 frozen verification bundle is not present." >&2
  exit 1
}

grep -q 'type FrozenVerificationBundle = {' "$PANEL" || {
  echo "FrozenVerificationBundle type is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.93-${STAMP}"

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

if (!text.includes('type VerificationBundleSelfCheck = "IDLE" | "VERIFIED" | "FAILED";')) {
  const anchor = `type HandoffSnapshotVerification = "IDLE" | "VERIFIED" | "FAILED";`;
  if (!text.includes(anchor)) {
    throw new Error("HandoffSnapshotVerification anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
type VerificationBundleSelfCheck = "IDLE" | "VERIFIED" | "FAILED";`,
  );
}

if (!text.includes("const [verificationBundleSelfCheck, setVerificationBundleSelfCheck]")) {
  const anchor = `  const [frozenVerificationBundle, setFrozenVerificationBundle] =
    useState<FrozenVerificationBundle | null>(null);`;

  if (!text.includes(anchor)) {
    throw new Error("frozenVerificationBundle state anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}
  const [verificationBundleSelfCheck, setVerificationBundleSelfCheck] =
    useState<VerificationBundleSelfCheck>("IDLE");`,
  );
}

if (!text.includes("function fingerprintVerificationBundleText(")) {
  const anchor = "function freezeVerificationBundle(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("freezeVerificationBundle anchor not found");

  const helper = `function fingerprintVerificationBundleText(
  textValue: string,
): string {
  let hash = 2166136261;

  for (let index = 0; index < textValue.length; index += 1) {
    hash ^= textValue.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }

  return \`fnv1a32-\${(hash >>> 0).toString(16).padStart(8, "0")}\`;
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

if (!text.includes("function verificationBundleCanonicalText(")) {
  const anchor = "function fingerprintVerificationBundleText(";
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("fingerprintVerificationBundleText anchor not found");

  const helper = `function verificationBundleCanonicalText(
  bundle: FrozenVerificationBundle,
): string {
  return bundle.text
    .split("\\n")
    .filter((line) => !line.startsWith("Bundle fingerprint: "))
    .join("\\n");
}

`;

  text = text.slice(0, idx) + helper + text.slice(idx);
}

if (!text.includes("const verifyFrozenVerificationBundle = useCallback(")) {
  const anchor = `  const copyHandoffVerificationBundle = useCallback(async () => {`;
  const idx = text.indexOf(anchor);
  if (idx < 0) throw new Error("copyHandoffVerificationBundle anchor not found");

  const callback = `  const verifyFrozenVerificationBundle = useCallback(() => {
    if (!frozenVerificationBundle) {
      setVerificationBundleSelfCheck("FAILED");
      return;
    }

    const canonical = verificationBundleCanonicalText(
      frozenVerificationBundle,
    );
    const recalculated = fingerprintVerificationBundleText(canonical);

    setVerificationBundleSelfCheck(
      recalculated === frozenVerificationBundle.fingerprint
        ? "VERIFIED"
        : "FAILED",
    );
  }, [frozenVerificationBundle]);

`;

  text = text.slice(0, idx) + callback + text.slice(idx);
}

if (!text.includes('setVerificationBundleSelfCheck("IDLE")')) {
  const anchor = `  useEffect(() => {
    if (handoffSnapshotVerification === "IDLE") return;

    const timer = window.setTimeout(
      () => setHandoffSnapshotVerification("IDLE"),
      5_000,
    );

    return () => window.clearTimeout(timer);
  }, [handoffSnapshotVerification]);`;

  if (!text.includes(anchor)) {
    throw new Error("handoff snapshot verification timeout anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

  useEffect(() => {
    if (verificationBundleSelfCheck === "IDLE") return;

    const timer = window.setTimeout(
      () => setVerificationBundleSelfCheck("IDLE"),
      5_000,
    );

    return () => window.clearTimeout(timer);
  }, [verificationBundleSelfCheck]);`,
  );
}

if (!text.includes('data-testid="director-audit-export-verify-frozen-bundle"')) {
  const anchor = `        {frozenVerificationBundle ? (
          <span
            className="scheduleAuditFrozenVerificationBundle"
            data-testid="director-audit-export-frozen-verification-bundle"
          >
            Verification bundle frozen{" "}
            {formatWhen(frozenVerificationBundle.createdAt)}
          </span>
        ) : null}`;

  if (!text.includes(anchor)) {
    throw new Error("Frozen verification bundle UI anchor not found");
  }

  text = text.replace(
    anchor,
    `${anchor}

        {frozenVerificationBundle ? (
          <button
            type="button"
            className="secondary"
            data-testid="director-audit-export-verify-frozen-bundle"
            onClick={verifyFrozenVerificationBundle}
          >
            Verify frozen bundle
          </button>
        ) : null}

        {verificationBundleSelfCheck !== "IDLE" ? (
          <span
            className="scheduleAuditVerificationBundleSelfCheck"
            data-testid="director-audit-export-verify-frozen-bundle-status"
            role="status"
            aria-live="polite"
          >
            {verificationBundleSelfCheck === "VERIFIED"
              ? "Frozen verification bundle fingerprint verified."
              : "Frozen verification bundle fingerprint failed self-check."}
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

describe("Tournament scheduling 6.93 verification bundle self-check", () => {
  it("models bundle self-check status explicitly", () => {
    expect(panel).toContain(
      'type VerificationBundleSelfCheck = "IDLE" | "VERIFIED" | "FAILED"',
    );
    expect(panel).toContain(
      "const [verificationBundleSelfCheck, setVerificationBundleSelfCheck]",
    );
  });

  it("recreates canonical frozen bundle text without the embedded fingerprint line", () => {
    expect(panel).toContain(
      "function verificationBundleCanonicalText(",
    );
    expect(panel).toContain(
      '.filter((line) => !line.startsWith("Bundle fingerprint: "))',
    );
  });

  it("fingerprints only the stored frozen bundle text", () => {
    expect(panel).toContain(
      "function fingerprintVerificationBundleText(",
    );
    expect(panel).toContain(
      "const canonical = verificationBundleCanonicalText(",
    );
    expect(panel).toContain(
      "const recalculated = fingerprintVerificationBundleText(canonical)",
    );
  });

  it("compares the recalculated fingerprint to the stored frozen fingerprint", () => {
    expect(panel).toContain(
      "recalculated === frozenVerificationBundle.fingerprint",
    );
  });

  it("renders a dedicated frozen-bundle verification action", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-verify-frozen-bundle"',
    );
    expect(panel).toContain("Verify frozen bundle");
  });

  it("provides accessible pass/fail feedback", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-verify-frozen-bundle-status"',
    );
    expect(panel).toContain(
      "Frozen verification bundle fingerprint verified.",
    );
    expect(panel).toContain(
      "Frozen verification bundle fingerprint failed self-check.",
    );
    expect(panel).toContain('aria-live="polite"');
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
echo " SportsOS Milestone 6.93"
echo " Verification Bundle Self-Check"
echo "============================================="
echo
echo "Updated:"
echo "  $PANEL"
echo
echo "Added:"
echo "  $TEST"
echo
echo "Behavior:"
echo "  verifies frozen bundle against its own stored text"
echo "  ignores embedded fingerprint line during recalculation"
echo "  compares recalculated fingerprint to frozen fingerprint"
echo "  accessible verified/failed feedback"
echo "  independent of live investigation state"
echo "  no server mutation introduced"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
