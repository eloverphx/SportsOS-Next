import { expect, test } from "@playwright/test";
import { mockSetupComplete } from "./fixtures";

test.describe("authentication entry points", () => {
  test("login page renders the SportsOS sign-in form", async ({ page }) => {
    await page.goto("/login");

    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
    await expect(page.getByPlaceholder("Username or email")).toBeVisible();
    await expect(page.getByPlaceholder("Password")).toBeVisible();
    await expect(page.getByRole("button", { name: "Sign in" })).toBeVisible();
  });

  test("root route sends a configured installation to login", async ({ page }) => {
    await mockSetupComplete(page);
    await page.goto("/");

    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  });

  test("protected dashboard redirects to login without a stored session", async ({ page }) => {
    await page.goto("/dashboard");

    await expect(page).toHaveURL(/\/login$/);
  });
});
