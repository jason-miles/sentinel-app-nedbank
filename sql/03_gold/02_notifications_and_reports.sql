-- PRD §7 Actions layer: notifications + daily/weekly reports.

-- High-severity alert feed for email notifications (severity >= high).
-- A scheduled job reads new rows here and emails the assigned analyst with a
-- one-line explanation + deep link into the app.
CREATE OR REPLACE VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.v_high_severity_alerts AS
SELECT
  fa.alert_id, fa.alert_type, fa.severity, fa.primary_entity_id,
  fa.score, fa.explanation, fa.triggered_at,
  -- deep link into the Databricks App alert-detail page
  concat('https://nedbank-fraud-aml-7474654808133980.aws.databricksapps.com/alerts/', fa.alert_id) AS app_link
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.fraud_alerts fa
WHERE fa.severity IN ('high', 'critical');

-- Weekly report narrative source (numbers reconcile via metric view semantics).
CREATE OR REPLACE VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.v_weekly_report AS
SELECT
  alert_type,
  count(*) AS alerts_this_week,
  sum(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) AS critical_this_week,
  count(DISTINCT primary_entity_id) AS entities
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.fraud_alerts
WHERE triggered_at >= current_timestamp() - INTERVAL 7 DAYS
GROUP BY alert_type;
