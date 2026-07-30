"use client";

import { useCallback, useEffect, useState } from "react";
import { AuthGate } from "../../components/AuthGate";
import { AppShell } from "../../components/AppShell";
import { API } from "../../lib/api";

interface HealthResponse {
  readonly status?: string;
  readonly services?: Record<string, string>;
  readonly uptime?: number;
}

interface PlatformResponse {
  readonly success: boolean;
  readonly requestId: string;
  readonly data: {
    readonly name: string;
    readonly version: string;
    readonly environment: string;
    readonly documentation: string;
  };
}

interface VersionResponse {
  readonly success: boolean;
  readonly requestId: string;
  readonly data: {
    readonly name: string;
    readonly version: string;
    readonly nodeVersion: string;
  };
}

interface ReadyResponse {
  readonly success: boolean;
  readonly requestId: string;
  readonly data: {
    readonly status: string;
  };
}

const SERVICE_NAMES = ["mysql", "redis", "mqtt", "minio"] as const;

function formatUptime(seconds: number | undefined): string {
  if (seconds === undefined) {
    return "Not reported";
  }

  const totalSeconds = Math.floor(seconds);
  const days = Math.floor(totalSeconds / 86_400);
  const hours = Math.floor((totalSeconds % 86_400) / 3_600);
  const minutes = Math.floor((totalSeconds % 3_600) / 60);

  return [days > 0 ? `${days}d` : "", hours > 0 ? `${hours}h` : "", `${minutes}m`]
    .filter(Boolean)
    .join(" ");
}

export default function SystemHealthPage() {
  const [health, setHealth] = useState<HealthResponse | null>(null);

  const [platform, setPlatform] = useState<PlatformResponse | null>(null);

  const [version, setVersion] = useState<VersionResponse | null>(null);

  const [ready, setReady] = useState<ReadyResponse | null>(null);

  const [lastChecked, setLastChecked] = useState<Date | null>(null);

  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  const loadStatus = useCallback(async (): Promise<void> => {
    setError("");

    try {
      const responses = await Promise.all([
        fetch(`${API}/health`),
        fetch(`${API}/`),
        fetch(`${API}/version`),
        fetch(`${API}/ready`),
      ]);

      if (responses.some((response) => !response.ok)) {
        throw new Error("One or more system-status requests failed");
      }

      const [healthResponse, platformResponse, versionResponse, readyResponse] = await Promise.all([
        responses[0].json() as Promise<HealthResponse>,
        responses[1].json() as Promise<PlatformResponse>,
        responses[2].json() as Promise<VersionResponse>,
        responses[3].json() as Promise<ReadyResponse>,
      ]);

      setHealth(healthResponse);
      setPlatform(platformResponse);
      setVersion(versionResponse);
      setReady(readyResponse);
      setLastChecked(new Date());
    } catch (caughtError) {
      setError(caughtError instanceof Error ? caughtError.message : "Could not load system health");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadStatus();

    const timer = window.setInterval(() => {
      void loadStatus();
    }, 30_000);

    return () => {
      window.clearInterval(timer);
    };
  }, [loadStatus]);

  const overallOnline =
    ready?.data.status === "ready" &&
    SERVICE_NAMES.every((service) => health?.services?.[service] === "online");

  return (
    <AuthGate>
      <AppShell>
        <div className="pageHead">
          <div>
            <h1>System Health</h1>
            <p className="muted">API and infrastructure status for SportsOS.</p>
          </div>

          <button className="secondary" disabled={loading} onClick={() => void loadStatus()}>
            {loading ? "Checking…" : "Refresh"}
          </button>
        </div>

        {error && <p className="error">{error}</p>}

        <div className="cards">
          <div className="metric">
            <span>Overall status</span>
            <strong className={overallOnline ? "online" : "offline"}>
              {overallOnline ? "Online" : "Attention needed"}
            </strong>
          </div>

          <div className="metric">
            <span>API readiness</span>
            <strong className={ready?.data.status === "ready" ? "online" : "offline"}>
              {ready?.data.status ?? "Checking"}
            </strong>
          </div>

          <div className="metric">
            <span>Environment</span>
            <b>{platform?.data.environment ?? "Unknown"}</b>
          </div>

          <div className="metric">
            <span>API version</span>
            <b>{version?.data.version ?? "Unknown"}</b>
          </div>

          <div className="metric">
            <span>Node.js</span>
            <b>{version?.data.nodeVersion ?? "Unknown"}</b>
          </div>

          <div className="metric">
            <span>Uptime</span>
            <b>{formatUptime(health?.uptime)}</b>
          </div>
        </div>

        <section className="panel">
          <h2>Infrastructure services</h2>

          <div className="cards">
            {SERVICE_NAMES.map((service) => {
              const status = health?.services?.[service] ?? "checking";

              return (
                <div className="metric" key={service}>
                  <span>{service.toUpperCase()}</span>

                  <strong className={status === "online" ? "online" : "offline"}>{status}</strong>
                </div>
              );
            })}
          </div>
        </section>

        <section className="panel">
          <h2>Platform details</h2>

          <div className="activity">
            <div>
              <b>API name</b>
              <span>{platform?.data.name ?? "SportsOS API"}</span>
            </div>

            <div>
              <b>Documentation</b>
              <span>{platform?.data.documentation ?? "/docs"}</span>
            </div>

            <div>
              <b>Last request ID</b>
              <span>{ready?.requestId ?? platform?.requestId ?? "Unavailable"}</span>
            </div>

            <div>
              <b>Last checked</b>
              <time>{lastChecked ? lastChecked.toLocaleString() : "Not checked"}</time>
            </div>
          </div>
        </section>
      </AppShell>
    </AuthGate>
  );
}
