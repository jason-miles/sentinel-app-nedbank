import { test, expect, Page } from "@playwright/test";

// Stub the SAR-flow endpoints so the e2e run needs no warehouse / LLM.
async function stubSar(page: Page) {
  await page.route("**/api/sherlock/personas", (r) =>
    r.fulfill({ json: [{ analyst_id: "AN_SARAH", analyst_name: "Sarah Chen", team_id: "TEAM_FR", team_name: "Fraud Investigations" }] }));

  await page.route("**/api/sar/orchestrate", (r) =>
    r.fulfill({ json: {
      case_id: "CASE-SCR-1", customer_name: "Marco Silva", scenario: "Sanctions/Watchlist Hit",
      priority: "critical", risk_score: 99, amount: 5420000,
      evidence: {
        transactions: [{ transaction_id: "TXN1", amount: 900000, direction: "credit" }],
        network: [{ counterparty_id: "TP1", full_name: "Onyx Capital", country: "KY" }],
        screening: [{ watch_name: "OFAC SDN — Marco Silva", list_type: "sanctions", confidence: "confirmed" }],
        pkyc: { risk_band: "critical" },
        adverse_media: [{ headline: "Cross-border laundering probe", source: "FT (synthetic)", published_at: "2026-05-11", score: 0.82 }],
      },
      agent_trace: [
        { agent: "transaction_analysis", finding: "Large passthrough consistent with layering." },
        { agent: "adverse_media", finding: "Confirmed OFAC SDN match." },
        { agent: "policy", finding: "STR obligation applies." },
      ],
      narrative: "Marco Silva moved 900000 in a rapid passthrough; confirmed OFAC SDN match per FT (synthetic). Recommend SAR.",
    } }));

  await page.route("**/api/sar/goaml/validate/**", (r) =>
    r.fulfill({ json: { valid: true, checks_total: 12, checks_passed: 12, issues: [] } }));

  let submitBody: any = null;
  await page.route("**/api/sherlock/sar/submit", (r) => {
    submitBody = JSON.parse(r.request().postData() || "{}");
    // enforce four-eyes server-side too (mirror the backend)
    if (!submitBody.approved_by || submitBody.approved_by === submitBody.filed_by)
      return r.fulfill({ json: { ok: false, error: "four-eyes" } });
    return r.fulfill({ json: { ok: true, sar_id: "CASE-SCR-1", approved_by: submitBody.approved_by } });
  });
  return () => submitBody;
}

test("SAR flow: evidence, goAML validation, four-eyes gate", async ({ page }) => {
  await stubSar(page);
  await page.goto("/sar/CASE-SCR-1");

  // Auto-gathered evidence + grounded media + multi-agent trace render
  await expect(page.getByText("Auto-Gathered Evidence Pack")).toBeVisible();
  await expect(page.getByText("Grounded Adverse Media")).toBeVisible();
  await expect(page.getByText("Cross-border laundering probe")).toBeVisible();

  // goAML validation badge shows valid (12/12)
  await expect(page.getByText(/goAML schema valid/)).toBeVisible();
  await expect(page.getByText(/12\/12/)).toBeVisible();

  // Four-eyes gate: File SAR disabled until a distinct approver is entered
  const fileBtn = page.getByRole("button", { name: "File SAR" });
  await expect(fileBtn).toBeDisabled();

  // Same-person approver keeps it disabled (filer is Sarah Chen)
  const approver = page.getByLabel("Four-eyes approver name");
  await approver.fill("Sarah Chen");
  await expect(fileBtn).toBeDisabled();

  // A distinct approver enables it → filing succeeds
  await approver.fill("Michael Rodriguez");
  await expect(fileBtn).toBeEnabled();
  await fileBtn.click();
  await expect(page.getByText("✓ SAR Filed")).toBeVisible();
});
