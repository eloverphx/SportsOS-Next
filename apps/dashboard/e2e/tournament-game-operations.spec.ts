import { expect, test } from "@playwright/test";

test.describe("Milestone 7.1 tournament game operations workspace", () => {
  test("loads a scheduled game and exposes non-mutating operations context", async ({
    page,
  }) => {
    await page.route("**/api/tournament/game-operations", async (route) => {
      await route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({
          success: true,
          data: {
            games: [
              {
                id: "game-701",
                homeTeam: { name: "Prior Lake Lakers" },
                awayTeam: { name: "Edina" },
                venue: { name: "Sports Arena" },
                rink: { name: "Rink A" },
                scheduledStart: "2026-08-11T18:00:00.000Z",
                status: "SCHEDULED",
              },
            ],
          },
        }),
      });
    });

    await page.route(
      "**/api/tournament/game-operations/game-701",
      async (route) => {
        await route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({
            success: true,
            data: {
              game: {
                id: "game-701",
                homeTeam: { name: "Prior Lake Lakers" },
                awayTeam: { name: "Edina" },
                venue: { name: "Sports Arena" },
                rink: { name: "Rink A" },
                scheduledStart: "2026-08-11T18:00:00.000Z",
                status: "SCHEDULED",
                scoringStatus: "NOT_STARTED",
              },
            },
          }),
        });
      },
    );

    await page.goto("/tournament/game-operations");

    await expect(
      page.getByTestId("game-operations-workspace"),
    ).toBeVisible();

    await page.getByTestId("game-operations-select").selectOption("game-701");

    await expect(page.getByTestId("game-operations-matchup")).toContainText(
      "Prior Lake Lakers vs Edina",
    );
    await expect(
      page.getByTestId("game-operations-readiness-count"),
    ).toHaveText("3/3");

    await expect(
      page.getByRole("button", { name: "Not enabled in 7.1" }),
    ).toHaveCount(4);

    await expect(page).toHaveURL(/gameId=game-701/);
  });
});
