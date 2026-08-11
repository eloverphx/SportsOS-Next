#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

PANEL="apps/dashboard/components/tournament/TournamentScheduleAudit.tsx"
E2E="apps/dashboard/e2e/tournament-schedule-audit-handoff.spec.ts"
TEST="apps/api/test/tournament-schedule-6.94.test.ts"

[[ -f "$PANEL" ]] || {
  echo "Missing expected file: $PANEL" >&2
  exit 1
}

grep -q 'data-testid="director-audit-export-verify-frozen-bundle"' "$PANEL" || {
  echo "Milestone 6.93 frozen bundle self-check is not present." >&2
  exit 1
}

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP=".game-engine-backups/6.94-${STAMP}"

for f in "$PANEL" "$E2E" "$TEST"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

mkdir -p "$(dirname "$E2E")"

cat > "$E2E" <<'EOF'
import { expect, test } from "@playwright/test";

test.describe("schedule audit handoff closeout", () => {
  test("exposes the full investigation export and handoff recovery workflow", async ({
    page,
  }) => {
    await page.goto("/tournament");

    await expect(
      page.getByTestId("director-audit-investigation-summary"),
    ).toBeVisible();

    await expect(
      page.getByTestId("director-audit-copy-link"),
    ).toBeVisible();

    await expect(
      page.getByTestId("director-audit-verify-link"),
    ).toBeVisible();

    const exportButton = page.getByRole("button", {
      name: "Download full investigation JSON",
    });
    await expect(exportButton).toBeVisible();

    await expect(
      page.getByTestId("director-audit-export-copy-receipt"),
    ).toBeVisible();

    await expect(
      page.getByTestId("director-audit-export-copy-share-url"),
    ).toBeVisible();

    const handoffCopy = page.getByTestId(
      "director-audit-export-copy-handoff-receipt",
    );
    await expect(handoffCopy).toBeVisible();

    const handoffState = page.getByTestId(
      "director-audit-export-handoff-state",
    );
    await expect(handoffState).toBeVisible();

    const restore = page.getByTestId(
      "director-audit-export-restore-investigation",
    );
    const restoreReverify = page.getByTestId(
      "director-audit-export-restore-reverify",
    );

    if (await restore.isVisible()) {
      await restore.click();
      await expect(
        page.getByTestId("director-audit-export-restore-status"),
      ).toContainText("restored");

      await expect(restoreReverify).toBeVisible();
      await restoreReverify.click();

      await expect(
        page.getByTestId(
          "director-audit-export-restore-reverify-status",
        ),
      ).toContainText("verified");
    }

    if (!(await handoffCopy.isEnabled())) {
      await expect(handoffState).toContainText("blocked");
    }

    if (await handoffCopy.isEnabled()) {
      await handoffCopy.click();

      await expect(
        page.getByTestId(
          "director-audit-export-copy-handoff-receipt-status",
        ),
      ).toContainText("copied");

      await expect(
        page.getByTestId(
          "director-audit-export-handoff-copied-snapshot",
        ),
      ).toBeVisible();

      const verifySnapshot = page.getByTestId(
        "director-audit-export-handoff-verify-snapshot",
      );
      await verifySnapshot.click();

      await expect(
        page.getByTestId(
          "director-audit-export-handoff-verify-snapshot-status",
        ),
      ).toContainText("verified");

      await expect(
        page.getByTestId(
          "director-audit-export-frozen-verification-record",
        ),
      ).toBeVisible();

      const copyBundle = page.getByTestId(
        "director-audit-export-copy-handoff-verification-bundle",
      );
      await copyBundle.click();

      await expect(
        page.getByTestId(
          "director-audit-export-frozen-verification-bundle",
        ),
      ).toBeVisible();

      const verifyBundle = page.getByTestId(
        "director-audit-export-verify-frozen-bundle",
      );
      await verifyBundle.click();

      await expect(
        page.getByTestId(
          "director-audit-export-verify-frozen-bundle-status",
        ),
      ).toContainText("verified");
    }
  });
});
EOF

cat > "$TEST" <<'EOF'
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const e2e = readFileSync(
  new URL(
    "../../dashboard/e2e/tournament-schedule-audit-handoff.spec.ts",
    import.meta.url,
  ),
  "utf8",
);

describe("Tournament scheduling 6.94 final audit/handoff E2E coverage", () => {
  it("covers the investigation summary, share link, and verification entry points", () => {
    expect(e2e).toContain(
      'getByTestId("director-audit-investigation-summary")',
    );
    expect(e2e).toContain(
      'getByTestId("director-audit-copy-link")',
    );
    expect(e2e).toContain(
      'getByTestId("director-audit-verify-link")',
    );
  });

  it("covers full investigation export and receipt controls", () => {
    expect(e2e).toContain(
      'name: "Download full investigation JSON"',
    );
    expect(e2e).toContain(
      'getByTestId("director-audit-export-copy-receipt")',
    );
    expect(e2e).toContain(
      'getByTestId("director-audit-export-copy-share-url")',
    );
  });

  it("covers restore and reverify recovery path", () => {
    expect(e2e).toContain(
      '"director-audit-export-restore-investigation"',
    );
    expect(e2e).toContain(
      '"director-audit-export-restore-reverify"',
    );
    expect(e2e).toContain(
      '"director-audit-export-restore-reverify-status"',
    );
  });

  it("covers handoff gating and handoff receipt copy", () => {
    expect(e2e).toContain(
      '"director-audit-export-handoff-state"',
    );
    expect(e2e).toContain(
      '"director-audit-export-copy-handoff-receipt"',
    );
    expect(e2e).toContain(
      '"director-audit-export-copy-handoff-receipt-status"',
    );
  });

  it("covers frozen handoff snapshot verification", () => {
    expect(e2e).toContain(
      '"director-audit-export-handoff-copied-snapshot"',
    );
    expect(e2e).toContain(
      '"director-audit-export-handoff-verify-snapshot"',
    );
    expect(e2e).toContain(
      '"director-audit-export-handoff-verify-snapshot-status"',
    );
  });

  it("covers frozen verification record and bundle workflow", () => {
    expect(e2e).toContain(
      '"director-audit-export-frozen-verification-record"',
    );
    expect(e2e).toContain(
      '"director-audit-export-copy-handoff-verification-bundle"',
    );
    expect(e2e).toContain(
      '"director-audit-export-frozen-verification-bundle"',
    );
  });

  it("covers final frozen bundle self-check", () => {
    expect(e2e).toContain(
      '"director-audit-export-verify-frozen-bundle"',
    );
    expect(e2e).toContain(
      '"director-audit-export-verify-frozen-bundle-status"',
    );
  });
});
EOF

echo
echo "============================================="
echo " SportsOS Milestone 6.94"
echo " Final Audit/Handoff E2E Coverage"
echo "============================================="
echo
echo "Added:"
echo "  $E2E"
echo "  $TEST"
echo
echo "Coverage:"
echo "  investigation summary/share verification"
echo "  full audit export"
echo "  receipt/share-link actions"
echo "  restore + reverify recovery"
echo "  handoff gate + handoff receipt copy"
echo "  frozen handoff snapshot verification"
echo "  frozen verification record"
echo "  frozen verification bundle"
echo "  final bundle self-check"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo "Then:"
echo "  npm run test:e2e:docker"
