import { defineConfig, devices } from "@playwright/test";

// E2E tests run against the built app served by `vite preview`. API calls are stubbed
// via route interception inside each test, so no backend/warehouse is required — the
// suite is fully self-contained and CI-friendly.
export default defineConfig({
  testDir: "./e2e",
  timeout: 30_000,
  fullyParallel: true,
  reporter: process.env.CI ? "list" : "html",
  use: {
    baseURL: "http://localhost:4173",
    trace: "on-first-retry",
  },
  webServer: {
    command: "npm run preview -- --port 4173",
    url: "http://localhost:4173",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
