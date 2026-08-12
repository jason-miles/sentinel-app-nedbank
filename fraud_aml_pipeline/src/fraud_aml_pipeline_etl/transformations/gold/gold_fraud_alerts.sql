-- Gold: fraud_alerts — the published union of all 10 detection families.
-- Common schema per PRD §6. This is the primary surface for the app alert queue.
-- Data-quality expectations (Lakeflow): the app/queue depend on these invariants, so
-- rows that violate them are dropped and surfaced in the pipeline's DQ metrics.
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.fraud_alerts (
  CONSTRAINT valid_alert_id   EXPECT (alert_id IS NOT NULL)                         ON VIOLATION DROP ROW,
  CONSTRAINT valid_severity   EXPECT (severity IN ('critical','high','medium','low')) ON VIOLATION DROP ROW,
  CONSTRAINT valid_score      EXPECT (score IS NULL OR (score >= 0 AND score <= 1))  ON VIOLATION DROP ROW,
  CONSTRAINT valid_alert_type EXPECT (alert_type IS NOT NULL)                        ON VIOLATION DROP ROW
) AS
SELECT * FROM detect_rapid_movement
UNION ALL SELECT * FROM detect_frequency_change
UNION ALL SELECT * FROM detect_circular_flow
UNION ALL SELECT * FROM detect_dormant_reactivation
UNION ALL SELECT * FROM detect_risk_rating_change
UNION ALL SELECT * FROM detect_adverse_media
UNION ALL SELECT * FROM detect_ubo_change
UNION ALL SELECT * FROM detect_account_takeover
UNION ALL SELECT * FROM detect_impossible_travel
UNION ALL SELECT * FROM detect_structuring;
