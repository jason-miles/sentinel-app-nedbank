import { test, expect, Page } from "@playwright/test";

// Stub the backend API so the e2e run needs no warehouse. Only the endpoints the
// landing + queue + investigation flow calls are mocked.
async function stubApi(page: Page) {
  await page.route("**/api/sherlock/personas", (r) =>
    r.fulfill({ json: [{ analyst_id: "AN_SARAH", analyst_name: "Sarah Chen", team_id: "TEAM_FR", team_name: "Fraud Investigations" }] }));

  await page.route("**/api/sherlock/queue/**", (r) =>
    r.fulfill({ json: {
      kpis: { critical: 3, high: 5, total: 20, new_alerts: 4 },
      weekly: [],
      active_alerts: [{
        case_id: "CASE-SCR-1", alert_num: 90001, customer_name: "Marco Silva",
        scenario: "Sanctions/Watchlist Hit", risk_score: 99, priority: "critical",
        amount: 5420000, days_open: 24, status: "new", ai_risk: 96.5, model_version: "2",
        sla: { target_days: 7, days_open: 24, days_remaining: -17, breached: true, status: "breached" },
      }],
    } }));

  await page.route("**/api/sherlock/case/**", (r) =>
    r.fulfill({ json: {
      case_id: "CASE-SCR-1", customer_name: "Marco Silva", scenario: "Sanctions/Watchlist Hit",
      priority: "critical", status: "new", risk_score: 99, ai_risk: 96.5, model_version: "2",
      amount: 5420000, days_open: 24, investigation_hours: 0, team_name: "Fraud Investigations",
      analyst_name: "Sarah Chen", flagged_transactions: [], counterparties: [], notes: [], actions: [],
      sla: { target_days: 7, days_open: 24, days_remaining: -17, breached: true, status: "breached" },
    } }));
}

test("landing page shows the two entry cards", async ({ page }) => {
  await stubApi(page);
  await page.goto("/");
  await expect(page.getByText("Executive Dashboard")).toBeVisible();
  await expect(page.getByText("Alert Investigation")).toBeVisible();
});

test("queue -> investigation navigation works", async ({ page }) => {
  await stubApi(page);
  await page.goto("/investigation");
  // The queue table renders the stubbed case
  await expect(page.getByText("Marco Silva")).toBeVisible();
  // SLA badge (breached) is shown
  await expect(page.getByText("Breached").first()).toBeVisible();
  // Drill into the case
  await page.getByRole("button", { name: /Investigate/i }).first().click();
  await expect(page.getByRole("heading", { name: /Marco Silva/ })).toBeVisible();
});
