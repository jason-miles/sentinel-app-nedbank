-- Fold sanctions screening + peer anomalies into sherlock_cases so they appear
-- in the exec Case Resolution Flow, scenario breakdown, priority heatmap, and
-- per-analyst queues alongside the original 9 scenarios.
--
-- Idempotent: removes any previously-folded rows (scenario in the two new
-- families) before re-inserting, so re-running does not duplicate.

USE CATALOG elexon_app_for_settlement_acc_catalog;

DELETE FROM nedbank_fraud_aml_gold.sherlock_cases
WHERE scenario IN ('Sanctions/Watchlist Hit', 'Behavioural Anomaly');

-- Sanctions/Watchlist cases -> Sanctions & Watchlist Screening team (Lerato Mokoena)
INSERT INTO nedbank_fraud_aml_gold.sherlock_cases
SELECT
  concat('CASE-SCR-', row_number() OVER (ORDER BY h.screening_id))            AS case_id,
  90000 + cast(row_number() OVER (ORDER BY h.screening_id) AS INT)            AS alert_num,
  coalesce(cust.customer_id, h.source_id)                                     AS customer_id,
  h.entity_name                                                              AS customer_name,
  'Sanctions/Watchlist Hit'                                                  AS scenario,
  CASE h.confidence WHEN 'confirmed' THEN 'critical' WHEN 'probable' THEN 'high' ELSE 'medium' END AS priority,
  'new'                                                                      AS status,
  'TEAM_SW'                                                                  AS team_id,
  'Sanctions & Watchlist Screening'                                          AS team_name,
  'AN_LISA'                                                                  AS analyst_id,
  'Lerato Mokoena'                                                           AS analyst_name,
  cast(round(60 + h.match_score * 39) AS INT)                                AS risk_score,
  0.0                                                                        AS amount,
  cast(pmod(cast(regexp_replace(h.watchlist_id,'[^0-9]','') AS INT), 30) AS INT) AS days_open,
  date_add(current_date(), 7)                                                AS due_date,
  0.0                                                                        AS investigation_hours,
  current_timestamp()                                                        AS opened_at
FROM nedbank_fraud_aml_gold.sanctions_screening_hits h
LEFT JOIN nedbank_fraud_aml_silver.customers cust ON cust.customer_id = h.source_id;

-- Behavioural anomaly cases -> owning team by segment risk (Fraud Investigations)
INSERT INTO nedbank_fraud_aml_gold.sherlock_cases
SELECT
  concat('CASE-ANO-', row_number() OVER (ORDER BY a.customer_id))            AS case_id,
  95000 + cast(row_number() OVER (ORDER BY a.customer_id) AS INT)           AS alert_num,
  a.customer_id,
  a.full_name                                                              AS customer_name,
  'Behavioural Anomaly'                                                    AS scenario,
  a.severity                                                               AS priority,
  'new'                                                                    AS status,
  'TEAM_FR'                                                                AS team_id,
  'Fraud Investigations'                                                   AS team_name,
  'AN_MARIA'                                                               AS analyst_id,
  'Anele Mbatha'                                                           AS analyst_name,
  cast(least(99, round(50 + a.anomaly_score * 8)) AS INT)                  AS risk_score,
  a.total_value                                                            AS amount,
  cast(pmod(cast(a.anomaly_score * 10 AS INT), 30) AS INT)                 AS days_open,
  date_add(current_date(), 5)                                              AS due_date,
  0.0                                                                      AS investigation_hours,
  current_timestamp()                                                      AS opened_at
FROM nedbank_fraud_aml_gold.peer_anomaly a;
