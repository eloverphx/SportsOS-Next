#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.9-enrollment-hardware-operations-integration"
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
TEST="packages/core/test/enrollment-hardware-operations-integration-12.9.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$PAGE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

node <<'NODE'
const fs = require("fs");

const file =
  "apps/dashboard/app/scoreboards/operations/page.tsx";

let text =
  fs.readFileSync(file, "utf8");

if (!text.includes("type EnrollmentRecord")) {
  const anchor =
    '"use client";';

  if (!text.includes(anchor)) {
    throw new Error(
      "Unable to locate client component marker.",
    );
  }

  const addition = `

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
};`;

  text =
    text.replace(
      anchor,
      anchor + addition,
    );
}

if (!text.includes("const [enrollments")) {
  const stateAnchor =
    "export default function";

  const fnIndex =
    text.indexOf(stateAnchor);

  if (fnIndex === -1) {
    throw new Error(
      "Unable to locate operations component.",
    );
  }

  const braceIndex =
    text.indexOf("{", fnIndex);

  if (braceIndex === -1) {
    throw new Error(
      "Unable to locate component body.",
    );
  }

  const insertion = `

  const [enrollments, setEnrollments] =
    useState<EnrollmentRecord[]>([]);

  const enrollmentByDeviceId =
    useMemo(
      () =>
        new Map(
          enrollments.map((record) => [
            record.deviceId,
            record,
          ]),
        ),
      [enrollments],
    );
`;

  text =
    text.slice(0, braceIndex + 1) +
    insertion +
    text.slice(braceIndex + 1);
}

if (!text.includes("/scoreboard-devices/enrollment")) {
  const effectAnchor =
    "useEffect(() =>";

  const firstEffect =
    text.indexOf(effectAnchor);

  if (firstEffect === -1) {
    throw new Error(
      "Unable to locate operations useEffect.",
    );
  }

  const loadSnippet = `
  useEffect(() => {
    let cancelled = false;

    async function loadEnrollments() {
      try {
        const response =
          await fetch(
            \`\${API_BASE}/scoreboard-devices/enrollment\`,
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

`;

  text =
    text.slice(0, firstEffect) +
    loadSnippet +
    text.slice(firstEffect);
}

if (!text.includes("Enrollment Trust")) {
  const headingCandidates = [
    "<h1",
    "<h2",
  ];

  let headingIndex = -1;

  for (const candidate of headingCandidates) {
    headingIndex =
      text.indexOf(candidate);

    if (headingIndex !== -1) {
      break;
    }
  }

  if (headingIndex === -1) {
    throw new Error(
      "Unable to locate page heading.",
    );
  }

  const card = `
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
          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Verified
            </div>
            <div className="mt-1 text-xl font-semibold">
              {
                enrollments.filter(
                  (record) =>
                    record.status === "VERIFIED",
                ).length
              }
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Pending
            </div>
            <div className="mt-1 text-xl font-semibold">
              {
                enrollments.filter(
                  (record) =>
                    record.status === "PENDING",
                ).length
              }
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Rejected
            </div>
            <div className="mt-1 text-xl font-semibold">
              {
                enrollments.filter(
                  (record) =>
                    record.status === "REJECTED",
                ).length
              }
            </div>
          </div>

          <div className="rounded-lg border border-slate-800 p-3">
            <div className="text-xs uppercase tracking-wide text-slate-500">
              Untrusted
            </div>
            <div className="mt-1 text-xl font-semibold">
              {
                enrollments.filter(
                  (record) =>
                    record.status !== "VERIFIED",
                ).length
              }
            </div>
          </div>
        </div>
      </section>

`;

  text =
    text.slice(0, headingIndex) +
    card +
    text.slice(headingIndex);
}

/*
 * Add a reusable trust badge near device IDs without depending on
 * one specific pre-existing component structure.
 */
if (!text.includes("function EnrollmentTrustBadge")) {
  const exportIndex =
    text.indexOf(
      "export default function",
    );

  if (exportIndex === -1) {
    throw new Error(
      "Unable to locate default component export.",
    );
  }

  const helper = `
function EnrollmentTrustBadge({
  record,
}: {
  record?: EnrollmentRecord;
}) {
  const status =
    record?.status ?? "UNENROLLED";

  return (
    <span
      className="rounded-full border border-slate-700 px-2 py-1 text-xs font-medium"
      title={
        record
          ? \`Firmware \${record.firmwareVersion} · Chip \${record.chipId}\`
          : "No enrollment record"
      }
    >
      {status}
    </span>
  );
}

`;

  text =
    text.slice(0, exportIndex) +
    helper +
    text.slice(exportIndex);
}

/*
 * If there is an obvious deviceId JSX rendering, append a trust badge once.
 */
if (!text.includes("enrollmentByDeviceId.get(")) {
  const patterns = [
    "{device.deviceId}",
    "{deviceId}",
    "{scoreboard.deviceId}",
  ];

  let patched = false;

  for (const pattern of patterns) {
    const idx =
      text.indexOf(pattern);

    if (idx !== -1) {
      const replacement =
        `${pattern}
                    <EnrollmentTrustBadge
                      record={
                        enrollmentByDeviceId.get(
                          ${
                            pattern === "{device.deviceId}"
                              ? "device.deviceId"
                              : pattern === "{scoreboard.deviceId}"
                              ? "scoreboard.deviceId"
                              : "deviceId"
                          },
                        )
                      }
                    />`;

      text =
        text.replace(
          pattern,
          replacement,
        );

      patched = true;
      break;
    }
  }

  if (!patched) {
    const noteAnchor =
      "Enrollment Trust";

    if (!text.includes(noteAnchor)) {
      throw new Error(
        "Unable to wire trust information into operations page.",
      );
    }
  }
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
  it("loads enrollment state into hardware operations", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "/scoreboard-devices/enrollment",
    );

    expect(page).toContain(
      "EnrollmentRecord",
    );
  });

  it("shows verified pending rejected and untrusted metrics", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
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
      expect(page).toContain(label);
    }
  });

  it("links hardware operations to enrollment management", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "/scoreboards/enrollment",
    );

    expect(page).toContain(
      "Manage Enrollment",
    );
  });

  it("defines an enrollment trust badge", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "EnrollmentTrustBadge",
    );

    expect(page).toContain(
      "No enrollment record",
    );
  });

  it("documents verified-only operational eligibility", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Only VERIFIED devices are eligible",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.9 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - enrollment trust data in hardware operations"
echo "  - verified / pending / rejected / untrusted metrics"
echo "  - enrollment trust badge support"
echo "  - link to /scoreboards/enrollment"
echo "  - 10-second enrollment refresh"
echo "  - verified-only operational eligibility guidance"
echo "  - Milestone 12.9 tests"
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
