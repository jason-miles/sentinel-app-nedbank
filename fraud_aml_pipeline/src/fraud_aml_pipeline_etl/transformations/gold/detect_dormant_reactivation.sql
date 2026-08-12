-- 6.4 Dormant account re-activation with high-value activity.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_dormant_reactivation AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
hits AS (
  SELECT a.account_id, a.customer_id, max(t.amount) AS max_amount,
         max(t.txn_ts) AS last_ts, collect_set(t.transaction_id) AS txn_ids
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions t
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a USING (account_id)
  CROSS JOIN cfg
  WHERE a.last_activity_before_ts < current_timestamp() - make_interval(0,0,0, cast(cfg.dormant_days AS INT),0,0,0)
    AND t.txn_ts >= current_date() - INTERVAL 7 DAYS
    AND t.amount >= cfg.dormant_high_value
  GROUP BY a.account_id, a.customer_id
)
SELECT
  concat('ALRT-DORM-', h.account_id)                      AS alert_id,
  'dormant_reactivation'                                  AS alert_type,
  'high'                                                  AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(h.account_id)                                     AS account_ids,
  h.txn_ids                                               AS transaction_ids,
  h.last_ts                                               AS triggered_at,
  0.8                                                     AS score,
  concat('Dormant account ', h.account_id, ' reactivated with a transaction of ',
         cast(round(h.max_amount) AS STRING), '.')         AS explanation,
  map('max_amount', cast(h.max_amount AS STRING))         AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM hits h
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = h.customer_id AND em.party_type = 'customer';
