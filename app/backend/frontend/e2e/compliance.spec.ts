import { test, expect, Page } from "@playwright/test";

async function stubCompliance(page: Page) {
  await page.route("**/api/sherlock/personas", (r) =>
    r.fulfill({ json: [{ analyst_id: "AN_SARAH", analyst_name: "Sarah Chen", team_id: "TEAM_FR", team_name: "Fraud Investigations" }] }));

  // Default tab (screening) — keep it simple, empty list is fine.
  await page.route("**/api/aml/screening**", (r) => r.fulfill({ json: [] }));

  await page.route("**/api/aml/model-governance", (r) =>
    r.fulfill({ json: {
      model_name: "sar_propensity_gbt", model_version: 2, algorithm: "GradientBoosting",
      run_id: "abc123", roc_auc: 0.65, precision: 0.54, recall: 0.33, f1: 0.41,
      model_fp: 32, rules_fp: 38, fp_reduction_pct: 15.8, n_features: 10, n_labelled: 660,
      positive_rate: 0.286, blend_model_weight: 0.7, blend_rules_weight: 0.3, governance_status: "validated",
    } }));
  await page.route("**/api/aml/model-drift", (r) =>
    r.fulfill({ json: { overall_status: "stable", features: [
      { feature: "risk_score", baseline_mean: 69, current_mean: 69, mean_shift_sigma: 0, drift_status: "stable" },
    ] } }));
  await page.route("**/api/aml/llm-eval", (r) =>
    r.fulfill({ json: { summary: { runs: 5, avg_groundedness: 0.82, avg_completeness: 0.84, guardrail_pass_rate: 1, overall_pass_rate: 1 }, runs: [] } }));
  await page.route("**/api/aml/audit**", (r) =>
    r.fulfill({ json: [{ event_ts: "2026-07-21T10:00:00", actor: "Sarah Chen", action: "sar_submit", case_id: "CASE-SCR-1", detail: "SAR Filed", source: "sar_filing" }] }));
}

test("Model Governance tab shows validation record + FP reduction + drift + eval", async ({ page }) => {
  await stubCompliance(page);
  await page.goto("/compliance");
  await page.getByRole("button", { name: "Model Governance" }).click();

  await expect(page.getByText("Model Validation Record — SAR-propensity classifier")).toBeVisible();
  await expect(page.getByText("15.8%").first()).toBeVisible();          // FP reduction KPI
  await expect(page.getByText(/Feature Drift Monitoring/)).toBeVisible();
  await expect(page.getByText(/LLM Evaluation & Guardrails/)).toBeVisible();
});

test("Audit Trail tab shows the defensible audit record", async ({ page }) => {
  await stubCompliance(page);
  await page.goto("/compliance");
  await page.getByRole("button", { name: "Audit Trail" }).click();

  await expect(page.getByText(/Defensible Audit Trail/)).toBeVisible();
  // Scope to the audit table row (avoid the hidden "Sarah Chen" persona <option>).
  const row = page.locator("table tbody tr", { hasText: "SAR filed" });
  await expect(row).toBeVisible();
  await expect(row).toContainText("Sarah Chen");
  await expect(row).toContainText("CASE-SCR-1");
});

test("dark mode toggle flips the theme", async ({ page }) => {
  await stubCompliance(page);
  await page.goto("/compliance");
  // The toggle button (☾ in light mode). Default may be light unless OS prefers dark.
  const html = page.locator("html");
  const before = await html.getAttribute("data-theme");
  await page.getByRole("button", { name: "Toggle theme" }).click();
  const after = await html.getAttribute("data-theme");
  expect(after).not.toBe(before);
  expect(["light", "dark"]).toContain(after);
});
