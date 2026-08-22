#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.9-enrollment-hardware-operations-integration-repair"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${ROOT}/.game-engine-backups/milestone-${MILESTONE}-${STAMP}"

ROOT_REAL="$(readlink -f "$ROOT" 2>/dev/null || true)"
EXPECTED_REAL="$(readlink -f "$EXPECTED_ROOT" 2>/dev/null || true)"

if [[ -z "$ROOT_REAL" || -z "$EXPECTED_REAL" ]]; then
  echo "ERROR: unable to resolve SportsOS-Next root." >&2
  exit 1
fi

if [[ "$ROOT_REAL" != "$EXPECTED_REAL" ]]; then
  echo "ERROR: refusing to run outside canonical SportsOS-Next root." >&2
  echo "Expected: $EXPECTED_REAL" >&2
  echo "Received: $ROOT_REAL" >&2
  exit 1
fi

for required in \
  "$ROOT/.git" \
  "$ROOT/package.json" \
  "$ROOT/apps/dashboard/app/scoreboards/operations/page.tsx" \
  "$ROOT/apps/dashboard/app/scoreboards/enrollment/page.tsx" \
  "$ROOT/apps/api/src/routes/scoreboardDeviceEnrollment.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
COMPONENT="apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx"
TEST="packages/core/test/enrollment-hardware-operations-integration-12.9.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$COMPONENT")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$COMPONENT")" \
  "$(dirname "$TEST")"

for file in "$PAGE" "$COMPONENT" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$COMPONENT" <<'EOF'
"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";

type EnrollmentRecord = {
  deviceId: string;
  firmwareVersion: string;
  chipId: string;
  status:
    | "UNENROLLED"
    | "PENDING"
    | "VERIFIED"
    | "REJECTED";
  firstSeenAt: string;
  lastSeenAt: string;
  verifiedAt: string | null;
};

type EnrollmentResponse = {
  success: boolean;
  data?: {
    devices?: EnrollmentRecord[];
  };
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function EnrollmentTrustPanel() {
  const [
    enrollments,
    setEnrollments,
  ] = useState<EnrollmentRecord[]>([]);

  const [
    loading,
    setLoading,
  ] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadEnrollments() {
      try {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-devices/enrollment`,
            {
              cache: "no-store",
            },
          );

        const json =
          (await response.json()) as EnrollmentResponse;

        if (!cancelled) {
          setEnrollments(
            json?.data?.devices ?? [],
          );
        }
      } catch {
        if (!cancelled) {
          setEnrollments([]);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void loadEnrollments();

    const interval =
      window.setInterval(
        () => {
          void loadEnrollments();
        },
        10000,
      );

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const counts =
    useMemo(
      () => ({
        verified:
          enrollments.filter(
            (record) =>
              record.status ===
              "VERIFIED",
          ).length,
        pending:
          enrollments.filter(
            (record) =>
              record.status ===
              "PENDING",
          ).length,
        rejected:
          enrollments.filter(
            (record) =>
              record.status ===
              "REJECTED",
          ).length,
        untrusted:
          enrollments.filter(
            (record) =>
              record.status !==
              "VERIFIED",
          ).length,
      }),
      [enrollments],
    );

  return (
    <section className="mb-6 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">
            Enrollment Trust
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Only VERIFIED devices are eligible for authoritative assignment,
            synchronization, reconcile, and command operations.
          </p>
        </div>

        <a
          href="/scoreboards/enrollment"
          className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
        >
          Manage Enrollment
        </a>
      </div>

      <div className="mt-4 grid gap-3 sm:grid-cols-4">
        <Metric
          label="Verified"
          value={counts.verified}
        />
        <Metric
          label="Pending"
          value={counts.pending}
        />
        <Metric
          label="Rejected"
          value={counts.rejected}
        />
        <Metric
          label="Untrusted"
          value={counts.untrusted}
        />
      </div>

      {loading ? (
        <p className="mt-4 text-sm text-slate-500">
          Loading enrollment state…
        </p>
      ) : enrollments.length === 0 ? (
        <p className="mt-4 text-sm text-slate-500">
          No enrolled scoreboard devices yet.
        </p>
      ) : (
        <div className="mt-5 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-slate-500">
              <tr>
                <th className="pb-2 pr-4">
                  Device
                </th>
                <th className="pb-2 pr-4">
                  Trust
                </th>
                <th className="pb-2 pr-4">
                  Firmware
                </th>
                <th className="pb-2">
                  Chip ID
                </th>
              </tr>
            </thead>
            <tbody>
              {enrollments.map(
                (record) => (
                  <tr
                    key={record.deviceId}
                    className="border-t border-slate-800"
                  >
                    <td className="py-3 pr-4 font-medium">
                      {record.deviceId}
                    </td>
                    <td className="py-3 pr-4">
                      <EnrollmentTrustBadge
                        status={
                          record.status
                        }
                      />
                    </td>
                    <td className="py-3 pr-4 text-slate-400">
                      {record.firmwareVersion}
                    </td>
                    <td className="py-3 font-mono text-slate-400">
                      {record.chipId}
                    </td>
                  </tr>
                ),
              )}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

function Metric({
  label,
  value,
}: {
  label: string;
  value: number;
}) {
  return (
    <div className="rounded-lg border border-slate-800 p-3">
      <div className="text-xs uppercase tracking-wide text-slate-500">
        {label}
      </div>
      <div className="mt-1 text-xl font-semibold">
        {value}
      </div>
    </div>
  );
}

function EnrollmentTrustBadge({
  status,
}: {
  status: EnrollmentRecord["status"];
}) {
  return (
    <span className="rounded-full border border-slate-700 px-2 py-1 text-xs font-medium">
      {status}
    </span>
  );
}
EOF

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text =
  fs.readFileSync(file, "utf8");

const importLine =
  'import { EnrollmentTrustPanel } from "./EnrollmentTrustPanel";';

if (!text.includes(importLine)) {
  const importMatches =
    [...text.matchAll(/^import .*?;\s*$/gm)];

  if (importMatches.length > 0) {
    const last =
      importMatches[
        importMatches.length - 1
      ];

    const insertAt =
      last.index +
      last[0].length;

    text =
      text.slice(0, insertAt) +
      "\n" +
      importLine +
      text.slice(insertAt);
  } else {
    text =
      importLine +
      "\n" +
      text;
  }
}

if (!text.includes("<EnrollmentTrustPanel")) {
  const returnMatch =
    text.match(/return\s*\(\s*<([A-Za-z][A-Za-z0-9.]*)\b[^>]*>/);

  if (!returnMatch || returnMatch.index === undefined) {
    throw new Error(
      "Unable to locate root JSX element in operations page.",
    );
  }

  const rootTag =
    returnMatch[0];

  const rootStart =
    returnMatch.index;

  const openEnd =
    text.indexOf(
      ">",
      rootStart,
    );

  if (openEnd === -1) {
    throw new Error(
      "Unable to locate end of root JSX opening tag.",
    );
  }

  text =
    text.slice(0, openEnd + 1) +
    "\n      <EnrollmentTrustPanel />" +
    text.slice(openEnd + 1);
}

fs.writeFileSync(file, text);
NODE

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.9 enrollment / hardware operations integration", () => {
  it("keeps enrollment client logic in a dedicated client component", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      '"use client"',
    );

    expect(component).toContain(
      "/scoreboard-devices/enrollment",
    );
  });

  it("shows verified pending rejected and untrusted metrics", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    for (const label of [
      "Verified",
      "Pending",
      "Rejected",
      "Untrusted",
    ]) {
      expect(component).toContain(label);
    }
  });

  it("links hardware operations to enrollment management", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "/scoreboards/enrollment",
    );

    expect(component).toContain(
      "Manage Enrollment",
    );
  });

  it("renders a device enrollment trust badge", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "EnrollmentTrustBadge",
    );

    expect(component).toContain(
      "record.status",
    );
  });

  it("integrates trust panel into the existing operations page without forcing it client-side", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      'import { EnrollmentTrustPanel } from "./EnrollmentTrustPanel";',
    );

    expect(page).toContain(
      "<EnrollmentTrustPanel />",
    );
  });

  it("documents verified-only operational eligibility", () => {
    const component = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/EnrollmentTrustPanel.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(component).toContain(
      "Only VERIFIED devices are eligible",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.9 repair installed"
echo "============================================================"
echo
echo "Repair:"
echo "  - no longer assumes operations/page.tsx is a client component"
echo "  - preserves the existing server component"
echo "  - adds EnrollmentTrustPanel as a dedicated client component"
echo "  - injects panel into the existing root JSX"
echo "  - keeps enrollment polling/state isolated from server rendering"
echo "  - updates Milestone 12.9 regression tests"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then rebuild dashboard:"
echo "  docker compose up -d --build dashboard"
echo
echo "Next after green:"
echo "  Milestone 12.10 - Device Lifecycle / Deployment Closeout"
