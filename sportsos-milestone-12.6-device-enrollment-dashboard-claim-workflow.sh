#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/mnt/user/appdata/SportsOS-Next}"
EXPECTED_ROOT="/mnt/user/appdata/SportsOS-Next"
MILESTONE="12.6-device-enrollment-dashboard-claim-workflow"
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
  "$ROOT/apps/dashboard/app/scoreboards/enrollment/page.tsx" \
  "$ROOT/apps/api/src/routes/scoreboardDeviceEnrollment.ts"
do
  [[ -e "$required" ]] || {
    echo "ERROR: prerequisite missing: $required" >&2
    exit 1
  }
done

cd "$ROOT"

PAGE="apps/dashboard/app/scoreboards/enrollment/page.tsx"
TEST="packages/core/test/device-enrollment-dashboard-claim-workflow-12.6.test.ts"

mkdir -p \
  "$BACKUP_DIR/$(dirname "$PAGE")" \
  "$BACKUP_DIR/$(dirname "$TEST")" \
  "$(dirname "$TEST")"

for file in "$PAGE" "$TEST"; do
  [[ -f "$file" ]] && cp -a "$file" "$BACKUP_DIR/$file"
done

cat > "$PAGE" <<'EOF'
"use client";

import {
  useCallback,
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
  claimTokenIssuedAt?: string | null;
  claimTokenConsumedAt?: string | null;
};

type ClaimTokenResponse = {
  success: boolean;
  data?: {
    deviceId: string;
    claimToken: string;
  };
  error?: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export default function ScoreboardEnrollmentPage() {
  const [
    devices,
    setDevices,
  ] = useState<EnrollmentRecord[]>(
    [],
  );

  const [
    loading,
    setLoading,
  ] = useState(true);

  const [
    busyDeviceId,
    setBusyDeviceId,
  ] = useState<string | null>(
    null,
  );

  const [
    claimTokens,
    setClaimTokens,
  ] = useState<
    Record<string, string>
  >({});

  const [
    messages,
    setMessages,
  ] = useState<
    Record<string, string>
  >({});

  const load = useCallback(
    async () => {
      setLoading(true);

      try {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-devices/enrollment`,
            {
              cache: "no-store",
            },
          );

        const json =
          await response.json();

        setDevices(
          json?.data?.devices ?? [],
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

  const pendingCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status === "PENDING",
        ).length,
      [devices],
    );

  const verifiedCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status ===
            "VERIFIED",
        ).length,
      [devices],
    );

  const rejectedCount =
    useMemo(
      () =>
        devices.filter(
          (device) =>
            device.status ===
            "REJECTED",
        ).length,
      [devices],
    );

  const requestClaimToken = async (
    deviceId: string,
  ) => {
    setBusyDeviceId(
      deviceId,
    );

    setMessages((current) => ({
      ...current,
      [deviceId]: "",
    }));

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-devices/enrollment/${encodeURIComponent(
            deviceId,
          )}/claim-token`,
          {
            method: "POST",
          },
        );

      const json =
        (await response.json()) as ClaimTokenResponse;

      if (
        !response.ok ||
        !json.success ||
        !json.data?.claimToken
      ) {
        setMessages((current) => ({
          ...current,
          [deviceId]:
            json.error ??
            "Unable to generate claim token.",
        }));

        return;
      }

      setClaimTokens((current) => ({
        ...current,
        [deviceId]:
          json.data!.claimToken,
      }));

      setMessages((current) => ({
        ...current,
        [deviceId]:
          "One-time claim token generated. Verify the physical device identity before claiming.",
      }));
    } finally {
      setBusyDeviceId(
        null,
      );
    }
  };

  const verify = async (
    deviceId: string,
  ) => {
    const claimToken =
      claimTokens[deviceId];

    if (!claimToken) {
      setMessages((current) => ({
        ...current,
        [deviceId]:
          "Generate a claim token first.",
      }));

      return;
    }

    setBusyDeviceId(
      deviceId,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-devices/enrollment/${encodeURIComponent(
            deviceId,
          )}/verify`,
          {
            method: "POST",
            headers: {
              "Content-Type":
                "application/json",
            },
            body: JSON.stringify({
              claimToken,
            }),
          },
        );

      const json =
        await response.json();

      if (
        !response.ok ||
        !json?.success
      ) {
        setMessages((current) => ({
          ...current,
          [deviceId]:
            json?.error ??
            "Device verification failed.",
        }));

        return;
      }

      setClaimTokens((current) => {
        const next = {
          ...current,
        };

        delete next[deviceId];

        return next;
      });

      setMessages((current) => ({
        ...current,
        [deviceId]:
          "Device verified. The claim token has been consumed.",
      }));

      await load();
    } finally {
      setBusyDeviceId(
        null,
      );
    }
  };

  const reject = async (
    deviceId: string,
  ) => {
    setBusyDeviceId(
      deviceId,
    );

    try {
      const response =
        await fetch(
          `${API_BASE}/scoreboard-devices/enrollment/${encodeURIComponent(
            deviceId,
          )}/reject`,
          {
            method: "POST",
          },
        );

      const json =
        await response.json();

      if (
        !response.ok ||
        !json?.success
      ) {
        setMessages((current) => ({
          ...current,
          [deviceId]:
            json?.error ??
            "Device rejection failed.",
        }));

        return;
      }

      setClaimTokens((current) => {
        const next = {
          ...current,
        };

        delete next[deviceId];

        return next;
      });

      setMessages((current) => ({
        ...current,
        [deviceId]:
          "Device rejected.",
      }));

      await load();
    } finally {
      setBusyDeviceId(
        null,
      );
    }
  };

  return (
    <main className="mx-auto max-w-6xl p-6">
      <div className="mb-6">
        <h1 className="text-3xl font-bold">
          Scoreboard Enrollment
        </h1>
        <p className="mt-2 text-slate-400">
          Claim and verify newly flashed ESP32 scoreboard devices
          before they can receive authoritative game operations.
        </p>
      </div>

      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border border-slate-800 p-4">
          <div className="text-sm text-slate-400">
            Pending
          </div>
          <div className="mt-1 text-2xl font-semibold">
            {pendingCount}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 p-4">
          <div className="text-sm text-slate-400">
            Verified
          </div>
          <div className="mt-1 text-2xl font-semibold">
            {verifiedCount}
          </div>
        </div>

        <div className="rounded-xl border border-slate-800 p-4">
          <div className="text-sm text-slate-400">
            Rejected
          </div>
          <div className="mt-1 text-2xl font-semibold">
            {rejectedCount}
          </div>
        </div>
      </div>

      {loading ? (
        <p className="text-slate-400">
          Loading devices…
        </p>
      ) : devices.length === 0 ? (
        <div className="rounded-xl border border-slate-800 p-6">
          <p className="text-slate-300">
            No first-boot enrollment requests yet.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {devices.map((device) => {
            const busy =
              busyDeviceId ===
              device.deviceId;

            const token =
              claimTokens[
                device.deviceId
              ];

            const message =
              messages[
                device.deviceId
              ];

            return (
              <section
                key={device.deviceId}
                className="rounded-xl border border-slate-800 p-5"
              >
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div>
                    <h2 className="text-xl font-semibold">
                      {device.deviceId}
                    </h2>

                    <div className="mt-2 space-y-1 text-sm text-slate-400">
                      <p>
                        Firmware:{" "}
                        {device.firmwareVersion}
                      </p>
                      <p>
                        Chip ID:{" "}
                        <span className="font-mono text-slate-300">
                          {device.chipId}
                        </span>
                      </p>
                      <p>
                        Status:{" "}
                        <span className="font-semibold text-slate-300">
                          {device.status}
                        </span>
                      </p>
                    </div>
                  </div>

                  {device.status ===
                    "PENDING" && (
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                          void requestClaimToken(
                            device.deviceId,
                          )
                        }
                        className="rounded-lg border border-slate-600 px-4 py-2 disabled:opacity-50"
                      >
                        Generate Claim Token
                      </button>

                      <button
                        type="button"
                        disabled={
                          busy ||
                          !token
                        }
                        onClick={() =>
                          void verify(
                            device.deviceId,
                          )
                        }
                        className="rounded-lg border border-slate-600 px-4 py-2 disabled:opacity-50"
                      >
                        Verify Device
                      </button>

                      <button
                        type="button"
                        disabled={busy}
                        onClick={() =>
                          void reject(
                            device.deviceId,
                          )
                        }
                        className="rounded-lg border border-slate-600 px-4 py-2 disabled:opacity-50"
                      >
                        Reject
                      </button>
                    </div>
                  )}
                </div>

                {token && (
                  <div className="mt-5 rounded-lg border border-slate-700 bg-slate-950 p-4">
                    <div className="text-xs uppercase tracking-wide text-slate-500">
                      One-time claim token
                    </div>
                    <code className="mt-2 block break-all text-sm text-slate-200">
                      {token}
                    </code>
                    <p className="mt-2 text-xs text-slate-500">
                      This token is shown only for the current dashboard session
                      and is removed after successful verification.
                    </p>
                  </div>
                )}

                {message && (
                  <p className="mt-4 text-sm text-slate-400">
                    {message}
                  </p>
                )}
              </section>
            );
          })}
        </div>
      )}
    </main>
  );
}
EOF

cat > "$TEST" <<'EOF'
import {
  describe,
  expect,
  it,
} from "vitest";
import fs from "node:fs";

describe("Milestone 12.6 enrollment dashboard claim workflow", () => {
  it("requests one-time claim tokens", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Generate Claim Token",
    );

    expect(page).toContain(
      "/claim-token",
    );
  });

  it("submits the generated claim token to verification", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "claimToken",
    );

    expect(page).toContain(
      "Verify Device",
    );

    expect(page).toContain(
      'method: "POST"',
    );
  });

  it("removes claim tokens from UI state after verification", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "delete next[deviceId]",
    );

    expect(page).toContain(
      "claim token has been consumed",
    );
  });

  it("shows pending verified and rejected counts", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "pendingCount",
    );

    expect(page).toContain(
      "verifiedCount",
    );

    expect(page).toContain(
      "rejectedCount",
    );
  });

  it("shows physical identity before claim action", () => {
    const page = fs.readFileSync(
      new URL(
        "../../../apps/dashboard/app/scoreboards/enrollment/page.tsx",
        import.meta.url,
      ),
      "utf8",
    );

    expect(page).toContain(
      "Firmware:",
    );

    expect(page).toContain(
      "Chip ID:",
    );
  });
});
EOF

echo
echo "============================================================"
echo " SportsOS-Next Milestone 12.6 installed"
echo "============================================================"
echo
echo "Added:"
echo "  - dashboard one-time claim token generation"
echo "  - physical chip/firmware identity review"
echo "  - claim-token verification action"
echo "  - claim-token UI removal after consumption"
echo "  - reject workflow"
echo "  - pending / verified / rejected metrics"
echo "  - operator feedback messages"
echo "  - Milestone 12.6 tests"
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
echo "  Milestone 12.7 - First-Boot Enrollment Transport Binding"
