"use client";

import {
  useEffect,
  useMemo,
  useState,
} from "react";

type AuditRecord = {
  auditId: string;
  deviceId: string;
  gameId: string | null;
  inputId: string;
  inputType: string;
  sequence: number;
  disposition:
    | "ACCEPTED"
    | "REJECTED"
    | "IGNORED_DUPLICATE"
    | "EXECUTION_FAILED";
  error: string | null;
  createdAt: string;
};

const API_BASE =
  process.env.NEXT_PUBLIC_API_URL ??
  "http://192.168.5.3:4001";

export function PhysicalControlDiagnosticsPanel() {
  const [records, setRecords] =
    useState<AuditRecord[]>([]);
  const [loading, setLoading] =
    useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const response =
          await fetch(
            `${API_BASE}/scoreboard-control-audit?limit=50`,
            { cache: "no-store" },
          );
        const json =
          await response.json();

        if (!cancelled) {
          setRecords(
            json?.data?.records ?? [],
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
        5000,
      );

    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  const stats =
    useMemo(() => {
      const accepted =
        records.filter(
          (record) =>
            record.disposition ===
            "ACCEPTED",
        ).length;

      const rejected =
        records.filter(
          (record) =>
            record.disposition ===
              "REJECTED" ||
            record.disposition ===
              "EXECUTION_FAILED",
        ).length;

      const duplicates =
        records.filter(
          (record) =>
            record.disposition ===
            "IGNORED_DUPLICATE",
        ).length;

      return {
        accepted,
        rejected,
        duplicates,
      };
    }, [records]);

  return (
    <section className="mt-8 rounded-xl border border-slate-800 p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-xl font-semibold">
            Physical Control Diagnostics
          </h2>
          <p className="mt-1 text-sm text-slate-400">
            Recent ESP32 button input decisions and execution results.
          </p>
        </div>

        <div className="flex gap-2 text-xs">
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Accepted {stats.accepted}
          </span>
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Rejected {stats.rejected}
          </span>
          <span className="rounded-full border border-slate-700 px-2 py-1">
            Duplicate {stats.duplicates}
          </span>
        </div>
      </div>

      {loading ? (
        <p className="mt-4 text-sm text-slate-500">
          Loading physical control audit…
        </p>
      ) : records.length === 0 ? (
        <p className="mt-4 text-sm text-slate-500">
          No physical control events recorded yet.
        </p>
      ) : (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-slate-500">
              <tr>
                <th className="pb-2 pr-4">Time</th>
                <th className="pb-2 pr-4">Device</th>
                <th className="pb-2 pr-4">Game</th>
                <th className="pb-2 pr-4">Input</th>
                <th className="pb-2 pr-4">Result</th>
                <th className="pb-2">Error</th>
              </tr>
            </thead>
            <tbody>
              {records.map(
                (record) => (
                  <tr
                    key={record.auditId}
                    className="border-t border-slate-800"
                  >
                    <td className="py-3 pr-4 text-xs text-slate-400">
                      {record.createdAt}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {record.deviceId}
                    </td>
                    <td className="py-3 pr-4 font-mono text-xs">
                      {record.gameId ?? "—"}
                    </td>
                    <td className="py-3 pr-4">
                      {record.inputType}
                    </td>
                    <td className="py-3 pr-4">
                      {record.disposition}
                    </td>
                    <td className="py-3 text-slate-400">
                      {record.error ?? "—"}
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
