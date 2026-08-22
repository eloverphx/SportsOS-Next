#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="13.8-firmware-fleet-operations-dashboard"
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
  "$ROOT/apps/api/src/routes/scoreboardFirmwareReleases.ts" \
  "$ROOT/apps/api/src/routes/scoreboardFirmwareDeploymentStatus.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

cd "$ROOT"

PAGE="apps/dashboard/app/scoreboards/firmware/page.tsx"
OPS_PAGE="apps/dashboard/app/scoreboards/operations/page.tsx"
TEST="packages/core/test/firmware-fleet-operations-dashboard-13.8.test.ts"

for file in "$PAGE" "$OPS_PAGE" "$TEST"; do
  if [[ -f "$file" ]]; then
    rel="${file#$ROOT/}"
    mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
    cp -a "$file" "$BACKUP_DIR/$rel"
  fi
done

mkdir -p \
  "$(dirname "$PAGE")" \
  "$(dirname "$TEST")"

cat > "$PAGE" <<'EOF'
"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";

type FirmwareRelease = {
  releaseId: string;
  version: string;
  channel: string;
  target: string;
  createdAt: string;
  firmwareSizeBytes: number;
  mandatory: boolean;
};

type DeploymentReport = {
  deviceId: string;
  releaseId: string;
  previousVersion: string;
  targetVersion: string;
  status: string;
  progressPercent: number | null;
  error: string | null;
  reportedAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export default function FirmwareFleetPage() {
  const [
    releases,
    setReleases,
  ] = useState<FirmwareRelease[]>([]);

  const [
    reports,
    setReports,
  ] = useState<DeploymentReport[]>([]);

  const [
    loading,
    setLoading,
  ] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const [
          releaseResponse,
          reportResponse,
        ] = await Promise.all([
          fetch(
            `${API_BASE}/scoreboard-firmware/releases`,
            {
              cache: "no-store",
            },
          ),
          fetch(
            `${API_BASE}/scoreboard-firmware/deployments`,
            {
              cache: "no-store",
            },
          ),
        ]);

        const [
          releaseJson,
          reportJson,
        ] = await Promise.all([
          releaseResponse.json(),
          reportResponse.json(),
        ]);

        if (!cancelled) {
          setReleases(
            releaseJson?.data?.releases ?? [],
          );

          setReports(
            reportJson?.data?.reports ?? [],
          );
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void load();

    const interval =
      window.setInterval(
        () => {
          void load();
        },
        10000,
      );

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const latestByDevice =
    useMemo(() => {
      const map =
        new Map<string, DeploymentReport>();

      for (const report of reports) {
        if (!map.has(report.deviceId)) {
          map.set(
            report.deviceId,
            report,
          );
        }
      }

      return [
        ...map.values(),
      ];
    }, [reports]);

  const failedCount =
    latestByDevice.filter(
      (report) =>
        report.status === "FAILED",
    ).length;

  const updatingCount =
    latestByDevice.filter(
      (report) =>
        [
          "DOWNLOADING",
          "VERIFYING",
          "READY_TO_INSTALL",
          "INSTALLING",
          "REBOOTING",
        ].includes(
          report.status,
        ),
    ).length;

  const succeededCount =
    latestByDevice.filter(
      (report) =>
        report.status === "SUCCEEDED",
    ).length;

  return (
    <main className="mx-auto max-w-7xl p-6">
      <div className="mb-6 flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold">
            Firmware Fleet
          </h1>
          <p className="mt-2 text-slate-400">
            OTA releases and deployment state across SportsOS scoreboard devices.
          </p>
        </div>

        <a
          href="/scoreboards/operations"
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm"
        >
          Hardware Operations
        </a>
      </div>

      <div className="mb-6 grid gap-3 sm:grid-cols-4">
        <Metric
          label="Releases"
          value={releases.length}
        />
        <Metric
          label="Updating"
          value={updatingCount}
        />
        <Metric
          label="Succeeded"
          value={succeededCount}
        />
        <Metric
          label="Failed"
          value={failedCount}
        />
      </div>

      <section className="mb-8 rounded-xl border border-slate-800 p-5">
        <h2 className="text-xl font-semibold">
          Firmware Releases
        </h2>

        {releases.length === 0 ? (
          <p className="mt-4 text-sm text-slate-500">
            No registered OTA releases.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Version
                  </th>
                  <th className="pb-2 pr-4">
                    Channel
                  </th>
                  <th className="pb-2 pr-4">
                    Target
                  </th>
                  <th className="pb-2 pr-4">
                    Mandatory
                  </th>
                  <th className="pb-2">
                    Release ID
                  </th>
                </tr>
              </thead>
              <tbody>
                {releases.map(
                  (release) => (
                    <tr
                      key={release.releaseId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 font-medium">
                        {release.version}
                      </td>
                      <td className="py-3 pr-4">
                        {release.channel}
                      </td>
                      <td className="py-3 pr-4">
                        {release.target}
                      </td>
                      <td className="py-3 pr-4">
                        {release.mandatory
                          ? "Yes"
                          : "No"}
                      </td>
                      <td className="py-3 font-mono text-xs text-slate-400">
                        {release.releaseId}
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="rounded-xl border border-slate-800 p-5">
        <h2 className="text-xl font-semibold">
          Device Deployment Status
        </h2>

        {loading ? (
          <p className="mt-4 text-sm text-slate-500">
            Loading fleet status…
          </p>
        ) : latestByDevice.length === 0 ? (
          <p className="mt-4 text-sm text-slate-500">
            No OTA deployment reports yet.
          </p>
        ) : (
          <div className="mt-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-500">
                <tr>
                  <th className="pb-2 pr-4">
                    Device
                  </th>
                  <th className="pb-2 pr-4">
                    Current
                  </th>
                  <th className="pb-2 pr-4">
                    Target
                  </th>
                  <th className="pb-2 pr-4">
                    Status
                  </th>
                  <th className="pb-2 pr-4">
                    Progress
                  </th>
                  <th className="pb-2">
                    Error
                  </th>
                </tr>
              </thead>
              <tbody>
                {latestByDevice.map(
                  (report) => (
                    <tr
                      key={report.deviceId}
                      className="border-t border-slate-800"
                    >
                      <td className="py-3 pr-4 font-medium">
                        {report.deviceId}
                      </td>
                      <td className="py-3 pr-4">
                        {report.previousVersion}
                      </td>
                      <td className="py-3 pr-4">
                        {report.targetVersion}
                      </td>
                      <td className="py-3 pr-4">
                        <StatusBadge
                          status={
                            report.status
                          }
                        />
                      </td>
                      <td className="py-3 pr-4">
                        {report.progressPercent ??
                          "—"}
                        {report.progressPercent !==
                          null && "%"}
                      </td>
                      <td className="py-3 text-slate-400">
                        {report.error ??
                          "—"}
                      </td>
                    </tr>
                  ),
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
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
    <div className="rounded-xl border border-slate-800 p-4">
      <div className="text-sm text-slate-400">
        {label}
      </div>
      <div className="mt-1 text-2xl font-semibold">
        {value}
      </div>
    </div>
  );
}

function StatusBadge({
  status,
}: {
  status: string;
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

if (!text.includes('href="/scoreboards/firmware"')) {
  const candidates = [
    'href="/scoreboards/enrollment"',
    'href="/scoreboards"',
  ];

  let patched = false;

  for (const anchor of candidates) {
    const idx =
      text.indexOf(anchor);

    if (idx === -1) {
      continue;
    }

    const tagStart =
      text.lastIndexOf(
        "<a",
        idx,
      );

    const tagEnd =
      text.indexOf(
        "</a>",
        idx,
      );

    if (
      tagStart === -1 ||
      tagEnd === -1
    ) {
      continue;
    }

    const insertAt =
      tagEnd + 4;

    const link = `

        <a
          href="/scoreboards/firmware"
          className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
        >
          Firmware Fleet
        </a>`;

    text =
      text.slice(0, insertAt) +
      link +
      text.slice(insertAt);

    patched = true;
    break;
  }

  if (!patched) {
    const rootClose =
      text.lastIndexOf("</");

    if (rootClose === -1) {
      throw new Error(
        "Unable to locate operations page insertion point.",
      );
    }

    text =
      text.slice(0, rootClose) +
      `
      <a
        href="/scoreboards/firmware"
        className="rounded-lg border border-slate-700 px-3 py-2 text-sm"
      >
        Firmware Fleet
      </a>
` +
      text.slice(rootClose);
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

describe("Milestone 13.8 firmware fleet operations dashboard", () => {
  const page = fs.readFileSync(
    new URL(
      "../../../apps/dashboard/app/scoreboards/firmware/page.tsx",
      import.meta.url,
    ),
    "utf8",
  );

  it("loads firmware releases and deployment reports", () => {
    expect(page).toContain(
      "/scoreboard-firmware/releases",
    );

    expect(page).toContain(
      "/scoreboard-firmware/deployments",
    );
  });

  it("shows release updating succeeded and failed metrics", () => {
    for (const label of [
      "Releases",
      "Updating",
      "Succeeded",
      "Failed",
    ]) {
      expect(page).toContain(label);
    }
  });

  it("shows current and target versions per device", () => {
    expect(page).toContain(
      "previousVersion",
    );

    expect(page).toContain(
      "targetVersion",
    );
  });

  it("shows progress and deployment errors", () => {
    expect(page).toContain(
      "progressPercent",
    );

    expect(page).toContain(
      "report.error",
    );
  });

  it("links back to hardware operations", () => {
    expect(page).toContain(
      "/scoreboards/operations",
    );
  });

  it("links hardware operations to firmware fleet", () => {
    const operations = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/operations/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(operations).toContain(
      "/scoreboards/firmware",
    );

    expect(operations).toContain(
      "Firmware Fleet",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 13.8 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - /scoreboards/firmware fleet dashboard"
echo "  - firmware release inventory"
echo "  - latest per-device deployment state"
echo "  - current / target version visibility"
echo "  - deployment progress visibility"
echo "  - failure visibility"
echo "  - 10-second fleet refresh"
echo "  - hardware operations navigation link"
echo "  - Milestone 13.8 tests"
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
echo "  Milestone 13.9 - Fleet Update Orchestration / Rollout Controls"
