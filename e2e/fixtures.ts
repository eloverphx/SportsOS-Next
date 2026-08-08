import type { Page } from "@playwright/test";

export const mockGame = {
  id: 42,
  organizationName: "Prior Lake Lakers",
  organizationLogoUrl: null,
  organizationPrimaryColor: "#0f172a",
  organizationSecondaryColor: "#e2e8f0",
  seasonName: "2026-27",
  homeTeamName: "Lakers",
  homeTeamLogoUrl: null,
  homeTeamPrimaryColor: "#1d4ed8",
  homeTeamSecondaryColor: "#ffffff",
  awayTeamName: "Eagles",
  awayTeamLogoUrl: null,
  awayTeamPrimaryColor: "#b91c1c",
  awayTeamSecondaryColor: "#ffffff",
  scheduledStart: "2026-08-08T19:00:00.000Z",
  timezone: "America/Chicago",
  venue: "Sports Arena",
  status: "LIVE",
  gamePhase: "REGULATION",
  homeScore: 3,
  awayScore: 2,
  period: 2,
  periodLengthMs: 1_200_000,
  clockRemainingMs: 542_000,
  clockRunning: false,
  clockStartedAt: null,
  intermissionRemainingMs: 0,
  intermissionRunning: false,
  intermissionStartedAt: null,
  regulationPeriods: 3,
  regulationPeriodLengthMs: 1_200_000,
  intermissionLengthMs: 900_000,
  overtimeEnabled: true,
  overtimeLengthMs: 300_000,
  periodLabel: "2",
  canAdvancePeriod: false,
  penalties: [],
} as const;

export async function mockSetupComplete(page: Page): Promise<void> {
  await page.route("**/setup/status", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ complete: true }),
    });
  });
}

export async function mockPublicScoreboard(page: Page, gameId = 42): Promise<void> {
  await page.route(`**/public/games/${gameId}/scoreboard`, async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ game: mockGame }),
    });
  });
}
