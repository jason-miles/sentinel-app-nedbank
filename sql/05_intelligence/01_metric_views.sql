-- Phase 3 Intelligence: Metric views over gold (semantic layer for Genie + Reports).
-- Metric views give Genie governed, consistent measures so numbers reconcile
-- across the app dashboard and NL answers (PRD §8 Genie space, §7.2 reports).

-- Fraud alerts metric view -------------------------------------------------
CREATE OR REPLACE VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.mv_fraud_alerts
WITH METRICS
LANGUAGE YAML
COMMENT 'Semantic metric view over fraud_alerts for Genie and reporting.'
AS $$
version: 0.1
source: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.fraud_alerts
dimensions:
  - name: Alert Type
    expr: alert_type
  - name: Severity
    expr: severity
  - name: Status
    expr: status
  - name: Primary Entity
    expr: primary_entity_id
  - name: Triggered Date
    expr: CAST(triggered_at AS DATE)
measures:
  - name: Alert Count
    expr: COUNT(1)
  - name: Distinct Entities
    expr: COUNT(DISTINCT primary_entity_id)
  - name: Critical Alerts
    expr: SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END)
  - name: Average Score
    expr: AVG(score)
$$;
