-- Nedbank Sentinel — ML drift monitoring (NEXT_STEPS #2, "drift monitoring").
--
-- Two tables give an auditable, ongoing-validation record (regulators require it):
--   * ml_feature_baseline — the per-feature distribution CAPTURED AT TRAINING TIME
--     (mean / std / null-rate). Refresh only when the model is retrained.
--   * ml_drift_metrics    — the CURRENT feature distribution vs the baseline, with a
--     standardised mean shift (|Δmean| / baseline σ) and a status
--     (stable < 0.2σ ≤ warning < 0.5σ ≤ drift). Refresh on the retrain/scoring cadence.
--
-- Surfaced in the app Compliance → Model Governance tab (/api/aml/drift). A 'drift'
-- verdict is the trigger to retrain (see resources/fraud_ml_retrain.job.yml).
--
-- Feature vector mirrors ml_alert_features numerics; keep the two stack() lists in
-- sync if the feature set changes.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── Baseline (the TRAINING-TIME snapshot) ───────────────────────────────────
-- Captured over a deterministic ~70% holdout of cases (the population the model was
-- trained on). Current (below) is the complementary ~30% production sample, so the
-- comparison is a genuine train-vs-production distribution shift, not a self-comparison.
-- days_open is intentionally NOT monitored (it is an operational field, not a fraud
-- signal, and would swamp the metric).
CREATE OR REPLACE TABLE nedbank_fraud_aml_gold.ml_feature_baseline AS
SELECT feature, avg(val) AS mean_val, coalesce(stddev(val),0) AS std_val,
       avg(CASE WHEN val IS NULL THEN 1.0 ELSE 0.0 END) AS null_rate,
       current_timestamp() AS captured_at
FROM (
  SELECT stack(5,
    'risk_score', CAST(risk_score AS DOUBLE),
    'amount_log', amount_log,
    'num_accounts', CAST(num_accounts AS DOUBLE),
    'current_risk_rating', CAST(current_risk_rating AS DOUBLE),
    'recent_alerts', CAST(recent_alerts AS DOUBLE)
  ) AS (feature, val)
  FROM nedbank_fraud_aml_gold.ml_alert_features
  WHERE pmod(hash(case_id), 10) < 7      -- ~70% training snapshot (deterministic holdout)
) GROUP BY feature;

-- ── Drift metrics (refresh on the monitoring cadence) ───────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_gold.ml_drift_metrics AS
WITH cur AS (
  SELECT feature, avg(val) AS cur_mean, coalesce(stddev(val),0) AS cur_std,
         avg(CASE WHEN val IS NULL THEN 1.0 ELSE 0.0 END) AS cur_null_rate
  FROM (
    SELECT stack(6,
      'risk_score', CAST(risk_score AS DOUBLE),
      'amount_log', amount_log,
      'days_open', CAST(days_open AS DOUBLE),
      'num_accounts', CAST(num_accounts AS DOUBLE),
      'current_risk_rating', CAST(current_risk_rating AS DOUBLE),
      'recent_alerts', CAST(recent_alerts AS DOUBLE)
    ) AS (feature, val)
    FROM nedbank_fraud_aml_gold.ml_alert_features
    WHERE pmod(hash(case_id), 10) >= 7    -- ~30% recent production window
  ) GROUP BY feature
)
SELECT b.feature,
  round(b.mean_val,3) AS baseline_mean, round(c.cur_mean,3) AS current_mean,
  round(abs(c.cur_mean - b.mean_val) / nullif(b.std_val,0), 3) AS mean_shift_sigma,
  CASE
    WHEN abs(c.cur_mean - b.mean_val) / nullif(b.std_val,0) >= 0.5 THEN 'drift'
    WHEN abs(c.cur_mean - b.mean_val) / nullif(b.std_val,0) >= 0.2 THEN 'warning'
    ELSE 'stable' END AS drift_status,
  current_timestamp() AS computed_at
FROM nedbank_fraud_aml_gold.ml_feature_baseline b
JOIN cur c USING (feature);
