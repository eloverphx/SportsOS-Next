export type HealthState = "online" | "degraded" | "offline" | "pending";

export interface ServiceHealth {
  name: string;
  status: HealthState;
  latencyMs?: number;
  message?: string;
}

export interface HealthStatus {
  status: "healthy" | "degraded" | "unhealthy";
  uptimeSeconds?: number;
  services: ReadonlyArray<ServiceHealth>;
}