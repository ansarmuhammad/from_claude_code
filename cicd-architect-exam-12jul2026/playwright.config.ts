import { defineConfig, devices } from "@playwright/test";

/**
 * Playwright configuration for the e2e suite against web-frontend.
 * See tests/e2e/api-service.spec.ts for the UI contract under test - the CI
 * pipeline (.github/workflows/ci-cd-pipeline.yml) invokes this via:
 *   playwright test tests/e2e/
 */
export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: process.env.WEB_FRONTEND_URL || "http://localhost:3000",
    trace: "on-first-retry",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
