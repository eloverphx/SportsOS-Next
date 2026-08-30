#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED="/mnt/user/appdata/SportsOS-Next"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${ROOT}/.game-engine-backups/milestone-25.8-preflight-dashboard-${STAMP}"

[[ "$(readlink -f "$ROOT")" == "$(readlink -f "$EXPECTED")" ]] || {
  echo "ERROR: refusing to run outside $EXPECTED" >&2
  exit 1
}

cd "$ROOT"

PAGE="apps/dashboard/app/broadcast/deployment/page.tsx"
TEST="packages/core/test/preflight-deployment-dashboard-25.8.test.ts"
DOC="docs/BROADCAST-RELEASE-READINESS.md"

for required in \
  ".git" \
  "apps/dashboard/app/broadcast" \
  "apps/api/src/routes/broadcastSessionCoordinator.ts" \
  "$DOC"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $ROOT/$required" >&2
    echo "Repository was not modified." >&2
    exit 1
  }
done

for file in "$PAGE" "$TEST" "$DOC"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp -a "$file" "$BACKUP/$file"
  fi
done

mkdir -p "$(dirname "$PAGE")" "$(dirname "$TEST")"

cat > "$PAGE" <<'EOF'
"use client";

import {
  useCallback,
  useEffect,
  useState,
} from "react";

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

type Check = {
  id: string;
  ok: boolean;
  required: boolean;
  message: string;
};

type Readiness = {
  ready: boolean;
  checks: Check[];
};

type DeploymentManifest = {
  generatedAt: string;
  repository: {
    commit: string | null;
    branch: string | null;
    tag: string | null;
    dirty: boolean | null;
  };
  versions: {
    root: string | null;
    api: string | null;
    dashboard: string | null;
    node: string;
  };
};

type Payload = {
  release: Readiness | null;
  migration: Readiness | null;
  secrets: Readiness | null;
  rollback: Readiness | null;
  manifest: DeploymentManifest | null;
};

async function loadJson(path: string) {
  const response =
    await fetch(
      `${API_BASE}${path}`,
      {
        cache: "no-store",
      },
    );

  const json =
    await response.json();

  if (!response.ok) {
    throw new Error(
      json?.error ??
      `Request failed: ${path}`,
    );
  }

  return json?.data ?? null;
}

export default function DeploymentPreflightPage() {
  const [data, setData] =
    useState<Payload>({
      release: null,
      migration: null,
      secrets: null,
      rollback: null,
      manifest: null,
    });

  const [loading, setLoading] =
    useState(true);

  const [error, setError] =
    useState<string | null>(null);

  const load =
    useCallback(
      async () => {
        setLoading(true);

        try {
          const [
            release,
            migration,
            secrets,
            rollback,
            manifest,
          ] =
            await Promise.all([
              loadJson(
                "/broadcast-coordinator/release-readiness",
              ),
              loadJson(
                "/broadcast-coordinator/data-migration-readiness",
              ),
              loadJson(
                "/broadcast-coordinator/secret-environment-validation",
              ),
              loadJson(
                "/broadcast-coordinator/rollback-restore-readiness",
              ),
              loadJson(
                "/broadcast-coordinator/deployment-manifest",
              ),
            ]);

          setData({
            release,
            migration,
            secrets,
            rollback,
            manifest,
          });

          setError(null);
        } catch (err) {
          setError(
            err instanceof Error
              ? err.message
              : "Unable to load deployment preflight.",
          );
        } finally {
          setLoading(false);
        }
      },
      [],
    );

  useEffect(() => {
    void load();
  }, [load]);

  const allReady =
    [
      data.release,
      data.migration,
      data.secrets,
      data.rollback,
    ].every(
      (section) =>
        section?.ready === true,
    );

  const sections = [
    ["Release Readiness", data.release],
    ["Data Migration Readiness", data.migration],
    ["Secret / Environment Validation", data.secrets],
    ["Rollback / Restore Readiness", data.rollback],
  ] as const;

  return (
    <main className="mx-auto max-w-7xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <a
            href="/broadcast/operations"
            className="text-xs text-slate-500"
          >
            ← Broadcast Operations
          </a>

          <h1 className="mt-2 text-2xl font-bold">
            Deployment Preflight
          </h1>

          <p className="mt-1 text-sm text-slate-500">
            Release readiness, migration safety, secrets, rollback, and version identity in one view.
          </p>
        </div>

        <button
          type="button"
          onClick={() => void load()}
          disabled={loading}
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm disabled:opacity-50"
        >
          Refresh Preflight
        </button>
      </div>

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <div className="text-xs text-slate-500">
          Deployment Gate
        </div>

        <div className="mt-1 text-2xl font-bold">
          {allReady ? "READY" : "BLOCKED"}
        </div>

        <p className="mt-2 text-xs text-slate-500">
          A production release should proceed only when all required sections report READY.
        </p>
      </section>

      {error && (
        <div className="mt-4 rounded-xl border border-red-900/40 p-4 text-sm text-red-300">
          {error}
        </div>
      )}

      <section className="mt-6 grid gap-4 lg:grid-cols-2">
        {sections.map(
          ([title, section]) => (
            <div
              key={title}
              className="rounded-xl border border-slate-800 p-5"
            >
              <div className="flex items-center justify-between gap-3">
                <h2 className="text-lg font-semibold">
                  {title}
                </h2>

                <span className="rounded border border-slate-700 px-3 py-1 text-xs font-semibold">
                  {section?.ready ? "READY" : "BLOCKED"}
                </span>
              </div>

              <div className="mt-4 space-y-2">
                {section?.checks?.map(
                  (check) => (
                    <div
                      key={check.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="text-xs font-semibold">
                          {check.id}
                        </div>

                        <div className="text-xs">
                          {check.ok ? "PASS" : "FAIL"}
                        </div>
                      </div>

                      <div className="mt-1 text-xs text-slate-500">
                        {check.message}
                      </div>
                    </div>
                  ),
                ) ??
                (
                  <div className="text-xs text-slate-500">
                    No checks loaded.
                  </div>
                )}
              </div>
            </div>
          ),
        )}
      </section>

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <h2 className="text-lg font-semibold">
          Deployment Manifest
        </h2>

        {!data.manifest ? (
          <div className="mt-3 text-xs text-slate-500">
            Manifest unavailable.
          </div>
        ) : (
          <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-4">
            <div className="rounded border border-slate-800 p-3">
              <div className="text-xs text-slate-500">
                Root Version
              </div>
              <div className="mt-1 text-sm font-semibold">
                {data.manifest.versions.root ?? "unknown"}
              </div>
            </div>

            <div className="rounded border border-slate-800 p-3">
              <div className="text-xs text-slate-500">
                Commit
              </div>
              <div className="mt-1 break-all text-xs font-semibold">
                {data.manifest.repository.commit ??
                  "not available in runtime image"}
              </div>
            </div>

            <div className="rounded border border-slate-800 p-3">
              <div className="text-xs text-slate-500">
                Tag
              </div>
              <div className="mt-1 text-sm font-semibold">
                {data.manifest.repository.tag ?? "none"}
              </div>
            </div>

            <div className="rounded border border-slate-800 p-3">
              <div className="text-xs text-slate-500">
                Working Tree
              </div>
              <div className="mt-1 text-sm font-semibold">
                {data.manifest.repository.dirty === null
                  ? "UNKNOWN"
                  : data.manifest.repository.dirty
                    ? "DIRTY"
                    : "CLEAN"}
              </div>
            </div>
          </div>
        )}
      </section>

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <h2 className="text-lg font-semibold">
          Release Verification
        </h2>

        <pre className="mt-3 overflow-x-auto rounded border border-slate-800 p-4 text-xs text-slate-400">
{`npm run typecheck && npm test
docker compose up -d --build api dashboard
bash scripts/release-smoke-test.sh
npm run test:e2e:docker`}
        </pre>
      </section>
    </main>
  );
}
EOF

cat >> "$DOC" <<'EOF'

## Milestone 25.8 — Preflight deployment dashboard

SportsOS now includes a deployment preflight dashboard:

```text
/broadcast/deployment
```

The page consolidates release readiness, data migration readiness, secret/environment validation, rollback/restore readiness, and deployment manifest identity.

The overall gate is:

```text
READY
BLOCKED
```

`READY` requires every required readiness section to pass.

The dashboard is read-only and does not rotate secrets, run migrations, perform rollback, or change container state.
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 25.8 preflight deployment dashboard", () => {
  const page =
    fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/broadcast/deployment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

  it("provides deployment preflight page",()=> {
    expect(page).toContain("Deployment Preflight");
    expect(page).toContain("Deployment Gate");
  });

  it("loads all readiness surfaces",()=> {
    expect(page).toContain("/broadcast-coordinator/release-readiness");
    expect(page).toContain("/broadcast-coordinator/data-migration-readiness");
    expect(page).toContain("/broadcast-coordinator/secret-environment-validation");
    expect(page).toContain("/broadcast-coordinator/rollback-restore-readiness");
    expect(page).toContain("/broadcast-coordinator/deployment-manifest");
  });

  it("blocks unless every readiness section passes",()=> {
    expect(page).toContain("allReady");
    expect(page).toContain('"BLOCKED"');
    expect(page).toContain('"READY"');
  });

  it("shows deployment manifest identity",()=> {
    expect(page).toContain("Deployment Manifest");
    expect(page).toContain("Root Version");
    expect(page).toContain("Commit");
    expect(page).toContain("Tag");
  });

  it("shows release verification commands",()=> {
    expect(page).toContain("Release Verification");
    expect(page).toContain("release-smoke-test.sh");
    expect(page).toContain("test:e2e:docker");
  });

  it("does not expose write actions",()=> {
    expect(page).not.toContain('method: "POST"');
    expect(page).not.toContain('method: "DELETE"');
  });
});
EOF

echo "============================================================"
echo " SportsOS-Next Milestone 25.8 installed"
echo "============================================================"
echo "Added:"
echo "  - /broadcast/deployment"
echo "  - consolidated readiness dashboard"
echo "  - READY/BLOCKED deployment gate"
echo "  - deployment manifest identity"
echo "  - release verification commands"
echo "  - read-only preflight UI"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Run:"
echo "  npm run typecheck && npm test"
echo
echo "Then:"
echo "  docker compose up -d --build api dashboard"
echo "  bash scripts/release-readiness-diagnostics.sh"
echo "  bash scripts/release-smoke-test.sh"
echo "  npm run test:e2e:docker"
echo
echo "Next after green:"
echo "  Milestone 25.9 - Staging-to-Production Acceptance Rehearsal"
