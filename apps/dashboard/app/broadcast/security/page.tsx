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

type Section = {
  ready: boolean;
  checks: Check[];
};

type SecurityTelemetry = {
  ready: boolean;
  blockers: string[];
  sections: {
    credentialRotation: Section;
    secretEnvironment: Section;
    secretSource: Section;
    sessionInvalidation: Section;
  };
};

export default function SecurityTelemetryPage() {
  const [data, setData] =
    useState<SecurityTelemetry | null>(null);

  const [error, setError] =
    useState<string | null>(null);

  const load =
    useCallback(
      async () => {
        try {
          const response =
            await fetch(
              `${API_BASE}/broadcast-coordinator/security-telemetry`,
              {
                cache:
                  "no-store",
              },
            );

          const json =
            await response.json();

          if (!response.ok) {
            throw new Error(
              json?.error ??
              "Unable to load security telemetry.",
            );
          }

          setData(
            json?.data ??
            null,
          );
          setError(null);
        } catch (err) {
          setError(
            err instanceof Error
              ? err.message
              : "Unable to load security telemetry.",
          );
        }
      },
      [],
    );

  useEffect(() => {
    void load();
  }, [load]);

  const sections = data
    ? [
        [
          "Credential Rotation",
          data.sections.credentialRotation,
        ],
        [
          "Secret / Environment",
          data.sections.secretEnvironment,
        ],
        [
          "Secret Source",
          data.sections.secretSource,
        ],
        [
          "Session Invalidation",
          data.sections.sessionInvalidation,
        ],
      ] as const
    : [];

  return (
    <main className="mx-auto max-w-7xl p-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <a
            href="/broadcast/deployment"
            className="text-xs text-slate-500"
          >
            ← Deployment Preflight
          </a>

          <h1 className="mt-2 text-2xl font-bold">
            Security Telemetry
          </h1>

          <p className="mt-1 text-sm text-slate-500">
            Production credential, secret-source, session, and hardening readiness.
          </p>
        </div>

        <button
          type="button"
          onClick={() =>
            void load()
          }
          className="rounded-lg border border-slate-700 px-4 py-2 text-sm"
        >
          Refresh Security
        </button>
      </div>

      <section className="mt-6 rounded-xl border border-slate-800 p-5">
        <div className="text-xs text-slate-500">
          Security Gate
        </div>

        <div className="mt-1 text-2xl font-bold">
          {data?.ready
            ? "READY"
            : "BLOCKED"}
        </div>

        <div className="mt-3 text-xs text-slate-500">
          Required blockers:{" "}
          {data?.blockers?.length
            ? data.blockers.join(", ")
            : "none"}
        </div>
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
                  {section.ready
                    ? "READY"
                    : "BLOCKED"}
                </span>
              </div>

              <div className="mt-4 space-y-2">
                {section.checks.map(
                  (check) => (
                    <div
                      key={check.id}
                      className="rounded border border-slate-800 p-3"
                    >
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-xs font-semibold">
                          {check.id}
                        </span>

                        <span className="text-xs">
                          {check.ok
                            ? "PASS"
                            : "FAIL"}
                        </span>
                      </div>

                      <div className="mt-1 text-xs text-slate-500">
                        {check.message}
                      </div>
                    </div>
                  ),
                )}
              </div>
            </div>
          ),
        )}
      </section>
    </main>
  );
}
