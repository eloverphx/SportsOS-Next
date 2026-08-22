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
    | "REJECTED"
    | "RETIRED";
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
