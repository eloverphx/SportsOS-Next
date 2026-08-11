#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
E2E="apps/dashboard/e2e/tournament-schedule-audit-handoff.spec.ts"
TEST="apps/api/test/tournament-schedule-6.95.test.ts"
REPORT="milestone-6.95-audit-handoff-closeout.txt"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

[[ -f "$E2E" ]] || {
  echo "Missing expected E2E file: $E2E" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-verify-frozen-bundle"' "$PANEL" || {
  echo "Milestone 6.93 bundle self-check is not present." >&2
  exit 1
}

grep -q 'schedule audit handoff closeout' "$E2E" || {
  echo "Milestone 6.94 closeout E2E coverage is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.95-${STAMP}"

for f in "$TEST" "$REPORT"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

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

const e2e = readFileSync(
  new URL(
    "../../dashboard/e2e/tournament-schedule-audit-handoff.spec.ts",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.95 audit/handoff closeout baseline", () => {
  it("contains server-authoritative investigation controls", () => {
    expect(panel).toContain(
      'data-testid="director-audit-investigation-summary"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-copy-link"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-verify-link"',
    );
  });

  it("contains complete export integrity protections", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-integrity"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-pagination-guard"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-final-recheck"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-fingerprint"',
    );
  });

  it("contains recovery, handoff, and restore controls", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-restore-investigation"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-restore-reverify"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-state"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-copy-handoff-receipt"',
    );
  });

  it("contains frozen handoff and verification records", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-handoff-copied-snapshot"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-frozen-verification-record"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-frozen-verification-bundle"',
    );
  });

  it("contains final bundle self-verification", () => {
    expect(panel).toContain(
      'data-testid="director-audit-export-verify-frozen-bundle"',
    );
    expect(panel).toContain(
      'data-testid="director-audit-export-verify-frozen-bundle-status"',
    );
  });

  it("has E2E coverage for the full handoff path", () => {
    expect(e2e).toContain("schedule audit handoff closeout");
    expect(e2e).toContain(
      '"director-audit-export-copy-handoff-receipt"',
    );
    expect(e2e).toContain(
      '"director-audit-export-handoff-verify-snapshot"',
    );
    expect(e2e).toContain(
      '"director-audit-export-copy-handoff-verification-bundle"',
    );
    expect(e2e).toContain(
      '"director-audit-export-verify-frozen-bundle"',
    );
  });

  it("keeps the investigation audit workflow read-only", () => {
    expect(panel).not.toContain('method: "POST"');
    expect(panel).not.toContain('method: "PUT"');
    expect(panel).not.toContain('method: "DELETE"');
  });
});
EOF

cat > "$REPORT" <<EOF
SportsOS Milestone 6.95
Audit/Handoff Closeout Baseline
Generated: $(date -Iseconds)

Closeout scope:
- server-authoritative schedule audit filters/facets
- shareable investigation state
- link verification and expiry
- complete filtered JSON export
- export snapshot drift protection
- pagination safety and final total recheck
- evidence fingerprinting
- export receipts and trust metadata
- restore and reverify workflow
- handoff readiness gate
- frozen handoff receipt snapshot
- copied snapshot verification
- frozen verification record
- verification record fingerprint
- frozen verification bundle
- bundle fingerprint
- frozen bundle self-check
- final E2E workflow coverage

Required green gate:
npm run typecheck && \
npm test && \
npm run build && \
docker compose up -d --build api dashboard && \
npm run test:e2e:docker

When green, this portion is baseline-ready.
EOF

echo
echo "============================================="
echo " SportsOS Milestone 6.95"
echo " Audit/Handoff Closeout & Baseline Gate"
echo "============================================="
echo
echo "Added:"
echo "  $TEST"
echo "  $REPORT"
echo
echo "Verified prerequisites:"
echo "  6.93 bundle self-check present"
echo "  6.94 final E2E coverage present"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run the full closeout gate:"
echo
echo "  npm run typecheck && \\"
echo "  npm test && \\"
echo "  npm run build && \\"
echo "  docker compose up -d --build api dashboard && \\"
echo "  npm run test:e2e:docker"
echo
echo "If green, Milestone 6 audit/handoff work is COMPLETE."
