/**
 * End-to-end test for web-frontend (localhost:3000) talking to api-service.
 *
 * Exercises the real markup in apps/web-frontend/src/App.tsx:
 *   - [data-testid="health-indicator"] -> "API status: healthy|unavailable|checking..."
 *     populated from GET {REACT_APP_API_URL}/health
 *   - a text input with placeholder "Title"
 *   - a text input with placeholder "Description"
 *   - a submit button labelled "Add Task"
 *   - a plain <ul><li> list rendering "{title} - {description} ({status})"
 *     for every task returned by GET /api/v1/tasks
 */
import { test, expect } from "@playwright/test";

test.describe("web-frontend / api-service integration", () => {
  test("loads the home page", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveTitle("Web Frontend");
    await expect(page.getByRole("heading", { name: "Task Manager" })).toBeVisible();
  });

  test("shows a healthy status indicator backed by api-service /health", async ({
    page,
  }) => {
    await page.goto("/");
    const healthIndicator = page.getByTestId("health-indicator");
    await expect(healthIndicator).toBeVisible();
    await expect(healthIndicator).toContainText(/healthy/i, { timeout: 15_000 });
  });

  test("renders the task list container on load", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("ul")).toBeVisible();
  });

  test("creates a task via the UI form and shows it in the list", async ({
    page,
  }) => {
    await page.goto("/");

    const uniqueTitle = `E2E task ${Date.now()}`;

    await page.getByPlaceholder("Title").fill(uniqueTitle);
    await page
      .getByPlaceholder("Description")
      .fill("Created by the Playwright e2e suite");
    await page.getByRole("button", { name: "Add Task" }).click();

    await expect(page.locator("ul").getByText(uniqueTitle)).toBeVisible({
      timeout: 10_000,
    });
  });

  test("clears the form and keeps the task visible after reloading", async ({
    page,
  }) => {
    await page.goto("/");

    const uniqueTitle = `E2E persisted task ${Date.now()}`;
    await page.getByPlaceholder("Title").fill(uniqueTitle);
    await page
      .getByPlaceholder("Description")
      .fill("Should still be here after reload");
    await page.getByRole("button", { name: "Add Task" }).click();

    await expect(page.locator("ul").getByText(uniqueTitle)).toBeVisible({
      timeout: 10_000,
    });
    await expect(page.getByPlaceholder("Title")).toHaveValue("");

    await page.reload();

    await expect(page.locator("ul").getByText(uniqueTitle)).toBeVisible({
      timeout: 10_000,
    });
  });

  test("increments the visible task count after creating a task", async ({
    page,
  }) => {
    await page.goto("/");
    await expect(page.locator("ul")).toBeVisible();

    const taskItems = page.locator("ul li");
    const countBefore = await taskItems.count();

    const uniqueTitle = `E2E count task ${Date.now()}`;
    await page.getByPlaceholder("Title").fill(uniqueTitle);
    await page
      .getByPlaceholder("Description")
      .fill("Used to verify the list grows by one");
    await page.getByRole("button", { name: "Add Task" }).click();

    await expect(page.locator("ul").getByText(uniqueTitle)).toBeVisible({
      timeout: 10_000,
    });
    await expect(taskItems).toHaveCount(countBefore + 1);
  });
});
