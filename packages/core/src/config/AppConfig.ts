export interface AppConfig {
  nodeEnv: "development" | "test" | "production";

  appName: string;

  appVersion: string;

  port: number;

  host: string;

  logLevel: "trace" | "debug" | "info" | "warn" | "error";
}