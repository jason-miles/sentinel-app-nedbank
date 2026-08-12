-- Gold: alert_feedback — app write-back table (PRD §7.3 explainability + feedback loop).
-- NOT a Lakeflow pipeline dataset: the app writes rows here when an analyst
-- confirms/dismisses an alert. Kept as a plain managed Delta table so the
-- pipeline never tries to own or overwrite it.
CREATE TABLE IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_feedback (
  feedback_id      STRING,
  alert_id         STRING,
  status           STRING,     -- confirmed | dismissed | reviewing
  analyst_feedback STRING,     -- free-text reason
  analyst          STRING,
  created_at       TIMESTAMP
) USING DELTA
COMMENT 'App write-back: analyst confirm/dismiss + reason for each alert.';
