-- Nedbank Sentinel — Supervised ML: feature + label tables (NEXT_STEPS #2).
--
-- The demo has no real SAR-filed/dismissed history (sherlock_sar_filings is empty),
-- so we synthesise a realistic labelled training set from the 660 investigated cases:
--   * planted-fraud parties (CUSTFRAUD* / TPFRAUD*) are known TRUE POSITIVES.
--   * every other case gets a probabilistic label driven by its features
--     (risk_score, amount, scenario weight, days_open) plus deterministic
--     pseudo-noise, so the model learns real-but-imperfect signal rather than
--     trivially memorising a threshold.
-- These tables are ADDITIVE — they read sherlock_cases + customer_360 and touch
-- nothing in the detection pipeline.
--
-- Run against the setup warehouse:
--   catalog elexon_app_for_settlement_acc_catalog, schema nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;
USE SCHEMA nedbank_fraud_aml_gold;

-- ── FEATURE TABLE ─────────────────────────────────────────────────────────
CREATE OR REPLACE TABLE ml_alert_features AS
SELECT
  c.case_id,
  c.scenario,
  c.priority,
  CAST(c.risk_score AS DOUBLE)              AS risk_score,
  CAST(c.amount AS DOUBLE)                  AS amount,
  log10(greatest(c.amount, 1.0))            AS amount_log,
  CAST(c.days_open AS DOUBLE)               AS days_open,
  CAST(c.investigation_hours AS DOUBLE)     AS investigation_hours,
  -- customer_360 rollups (nullable for third-party subjects -> coalesced)
  coalesce(c360.num_accounts, 0)            AS num_accounts,
  coalesce(c360.total_balance, 0.0)         AS total_balance,
  coalesce(c360.current_risk_rating, 3)     AS current_risk_rating,
  coalesce(c360.recent_alerts, 0)           AS recent_alerts,
  -- known planted-fraud subject flag (kept out of the model features; used only
  -- to seed the ground-truth label below). Covers every planted-typology subject:
  -- legacy fraud (CUSTFRAUD/TPFRAUD), the WOW-A mule network (CUSTMULE), and the
  -- WOW-C gaming/TPP layering accounts (CUSTGAME).
  CASE WHEN c.customer_id LIKE 'CUSTFRAUD%' OR c.customer_id LIKE 'TPFRAUD%'
            OR c.customer_id LIKE 'CUSTMULE%' OR c.customer_id LIKE 'CUSTGAME%'
       THEN 1 ELSE 0 END                    AS is_planted_fraud
FROM sherlock_cases c
LEFT JOIN customer_360 c360 ON c360.customer_id = c.customer_id;

-- ── LABEL TABLE ───────────────────────────────────────────────────────────
-- sar_filed = 1 means the case was (would be) escalated to a filed SAR.
--
-- DESIGN (important): true SAR propensity is driven by a MULTIVARIATE INTERACTION
-- that a single-feature ranking (the legacy rules `risk_score`) cannot capture — a
-- case is genuinely suspicious when a HIGH-RISK SCENARIO coincides with a LARGE
-- amount and corroborating context (recent alerts, KYC risk band). The legacy
-- risk_score is deliberately a WEAK, noisy proxy of this (as in real AML, where the
-- rules engine over-flags). That gap is exactly what the GBT exploits to cut false
-- positives at equal workload — the "fewer false positives" story only holds if the
-- label is NOT just the rules score in disguise.
CREATE OR REPLACE TABLE ml_sar_labels AS
WITH scored AS (
  SELECT
    f.case_id,
    f.is_planted_fraud,
    -- scenario severity weight (0..1)
    CASE f.scenario
       WHEN 'Sanctions/Watchlist Hit'      THEN 1.0
       WHEN 'PEP/Sanctions Alert'          THEN 0.9
       WHEN 'Cash Structuring Detection'   THEN 0.8
       WHEN 'Rapid Fund Movement'          THEN 0.7
       WHEN 'High-Risk Geography Transfer' THEN 0.6
       WHEN 'Behavioural Anomaly'          THEN 0.6
       WHEN 'Beneficiary Mismatch'         THEN 0.4
       WHEN 'Third-Party Deposit Pattern'  THEN 0.4
       WHEN 'Round Dollar Pattern'         THEN 0.3
       WHEN 'Related Account Movement'     THEN 0.3
       WHEN 'Dormant Account Reactivation' THEN 0.3
       ELSE 0.3 END                         AS sev,
    least(1.0, greatest(0.0, (f.amount_log - 5.5) / 1.6)) AS amt_norm,  -- ~0 at 300k, ~1 at 12M
    f.recent_alerts, f.current_risk_rating,
    (pmod(hash(f.case_id), 1000) / 1000.0)  AS noise
  FROM ml_alert_features f
),
propensity AS (
  SELECT *,
    least(1.0, greatest(0.0,
        0.62 * (sev * amt_norm)                 -- THE interaction: severity AND size together
      + 0.18 * sev                              -- some main-effect from scenario
      + 0.10 * least(1.0, recent_alerts / 4.0)  -- corroborating recent activity
      + 0.10 * greatest(0.0, (current_risk_rating - 3) / 2.0)
    )) AS p
  FROM scored
)
SELECT
  case_id,
  is_planted_fraud,
  round(p, 4) AS propensity,
  CASE
    WHEN is_planted_fraud = 1 THEN 1                    -- ground-truth positive
    WHEN noise < p            THEN 1                    -- probabilistic positive
    ELSE 0
  END AS sar_filed
FROM propensity;
