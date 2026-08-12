-- 6.1 Rapid movement of funds (layering passthrough): big inflow then
-- near-equal outflow within 24h. Private MV feeding gold.fraud_alerts.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_rapid_movement AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
flows AS (
  SELECT a.account_id, a.customer_id,
         SUM(CASE WHEN t.direction='credit' THEN t.amount END) AS inflow,
         SUM(CASE WHEN t.direction='debit'  THEN t.amount END) AS outflow,
         -- earliest credit and latest debit, to confirm passthrough ordering
         MIN(CASE WHEN t.direction='credit' THEN t.txn_ts END) AS first_credit_ts,
         MAX(CASE WHEN t.direction='debit'  THEN t.txn_ts END) AS last_debit_ts,
         max(t.txn_ts) AS last_ts,
         collect_set(t.transaction_id) AS txn_ids
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions t
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a USING (account_id)
  WHERE t.txn_ts >= current_timestamp() - INTERVAL 24 HOURS
  GROUP BY a.account_id, a.customer_id
)
SELECT
  concat('ALRT-RM-', f.account_id)                       AS alert_id,
  'rapid_movement'                                        AS alert_type,
  CASE WHEN f.inflow >= 2000000 THEN 'critical' ELSE 'high' END AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(f.account_id)                                     AS account_ids,
  f.txn_ids                                               AS transaction_ids,
  f.last_ts                                               AS triggered_at,
  least(1.0, round(f.outflow / nullif(f.inflow,0), 3))    AS score,
  concat('Account ', f.account_id, ' moved ', cast(round(f.outflow) AS STRING),
         ' out against ', cast(round(f.inflow) AS STRING), ' in within 24h (passthrough).') AS explanation,
  map('inflow', cast(f.inflow AS STRING), 'outflow', cast(f.outflow AS STRING)) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM flows f
CROSS JOIN cfg
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = f.customer_id AND em.party_type = 'customer'
WHERE f.inflow >= cfg.rapid_min_amount
  AND f.outflow >= f.inflow * cfg.passthrough_ratio
  -- true layering signature: money must arrive before it leaves
  AND f.first_credit_ts IS NOT NULL AND f.last_debit_ts IS NOT NULL
  AND f.first_credit_ts <= f.last_debit_ts;
