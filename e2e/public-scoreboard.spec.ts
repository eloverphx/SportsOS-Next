import { expect, test } from "@playwright/test";
import { mockPublicScoreboard } from "./fixtures";

test.describe("public game surfaces", () => {
  test("public scoreboard renders an API game snapshot", async ({ page }) => {
    await mockPublicScoreboard(page);

    await page.goto("/games/42/scoreboard");

    await expect(page.getByText("Lakers", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("Eagles", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("3", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("2", { exact: true }).first()).toBeVisible();
  });

  test("broadcast overlay renders the same public snapshot", async ({ page }) => {
    await mockPublicScoreboard(page);

    await page.goto("/games/42/overlay?title=SportsOS%20Test");

    await expect(page.getByText("Lakers", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("Eagles", { exact: true }).first()).toBeVisible();
    await expect(page.getByText("SportsOS Test", { exact: true })).toBeVisible();
  });
});
