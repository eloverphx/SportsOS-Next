import { defineConfig, devices } from "@playwright/test";

const dashboardUrl = process.env.PLAYWRIGHT_BASE_URL ?? "http://127.0.0.1:4000";
const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://127.0.0.1:4001";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI ? [["github"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: dashboardUrl,
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  webServer: {
    command: "npm run dev --workspace=@sportsos/dashboard",
    url: dashboardUrl,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
    env: {
      ...process.env,
      NEXT_PUBLIC_API_URL: apiUrl,
      NEXT_TELEMETRY_DISABLED: "1",
    },
  },
});
