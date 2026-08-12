-- SherlockAML — Executive Overview aggregate views over sherlock_cases.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- KPI snapshot (Executive Overview tiles).
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_exec_kpis AS
SELECT
  round(sum(amount)/1e6, 2)                                            AS transaction_amount_m,
  count(*)                                                             AS case_volume,
  sum(CASE WHEN due_date BETWEEN current_date() AND current_date() + INTERVAL 14 DAYS
           AND status <> 'closed' THEN 1 ELSE 0 END)                   AS upcoming_deadlines,
  round(avg(investigation_hours), 2)                                   AS avg_investigation_hours,
  round(100.0 * sum(CASE WHEN status='closed' AND risk_score < 60 THEN 1 ELSE 0 END)
        / nullif(sum(CASE WHEN status='closed' THEN 1 ELSE 0 END),0), 1) AS false_positive_rate,
  sum(CASE WHEN due_date < current_date() AND status <> 'closed' THEN 1 ELSE 0 END) AS past_due_alerts
FROM nedbank_fraud_aml_gold.sherlock_cases;

-- Alerts by scenario (horizontal bar).
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_by_scenario AS
SELECT scenario, count(*) AS alerts FROM nedbank_fraud_aml_gold.sherlock_cases
GROUP BY scenario ORDER BY alerts DESC;

-- Alerts by priority x status (heatmap).
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_priority_status AS
SELECT priority, status, count(*) AS alerts FROM nedbank_fraud_aml_gold.sherlock_cases
GROUP BY priority, status;

-- Case resolution flow (Sankey): scenario -> team -> status.
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_resolution_flow AS
SELECT scenario AS source, team_name AS target, count(*) AS value
FROM nedbank_fraud_aml_gold.sherlock_cases GROUP BY scenario, team_name
UNION ALL
SELECT team_name AS source, status AS target, count(*) AS value
FROM nedbank_fraud_aml_gold.sherlock_cases GROUP BY team_name, status;

-- Team performance (Team Performance tab).
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_team_performance AS
SELECT team_name,
       count(*) AS cases,
       sum(CASE WHEN status='closed' THEN 1 ELSE 0 END) AS closed,
       sum(CASE WHEN due_date < current_date() AND status <> 'closed' THEN 1 ELSE 0 END) AS past_due,
       round(avg(investigation_hours), 2) AS avg_hours,
       round(avg(risk_score), 0) AS avg_risk
FROM nedbank_fraud_aml_gold.sherlock_cases GROUP BY team_name;

-- Daily new alerts (area chart) — cases opened per day.
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_daily_new AS
SELECT date(opened_at) AS d, count(*) AS alerts
FROM nedbank_fraud_aml_gold.sherlock_cases GROUP BY date(opened_at);

-- Outstanding alerts by due date (bar chart) — open cases bucketed by due date.
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.sherlock_outstanding AS
SELECT due_date, count(*) AS alerts
FROM nedbank_fraud_aml_gold.sherlock_cases WHERE status <> 'closed'
GROUP BY due_date;
