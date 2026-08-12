-- 6.10 Cash structuring (smurfing): repeated CASH deposits deliberately kept just
-- under the SA Cash Threshold Report (CTR) limit of R25,000 (FIC Act). A single
-- sub-threshold deposit is unremarkable; a cluster of them into one account inside a
-- short window is the textbook structuring signature — and the entry point to the
-- WOW-A mule-network narrative (each mule is structured into, then forwards on).
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_structuring AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
deposits AS (
  SELECT a.account_id, a.customer_id,
         count(*)                       AS near_deposits,
         sum(t.amount)                  AS total_cash_in,
         max(t.txn_ts)                  AS last_ts,
         collect_set(t.transaction_id)  AS txn_ids
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions t
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a USING (account_id)
  CROSS JOIN cfg
  WHERE t.direction = 'credit'
    AND t.channel IN ('cash_send','atm','branch')
    AND t.merchant_category = 'cash'
    -- near the CTR but under it: [struct_min_ratio * threshold, threshold)
    AND t.amount >= cfg.struct_min_ratio * cfg.ctr_threshold
    AND t.amount <  cfg.ctr_threshold
    AND t.txn_ts >= current_timestamp() - make_interval(0,0,0, cast(cfg.struct_window_days AS INT),0,0,0)
  GROUP BY a.account_id, a.customer_id
)
SELECT
  concat('ALRT-STRUCT-', d.account_id)                    AS alert_id,
  'structuring'                                           AS alert_type,
  CASE WHEN d.near_deposits >= 5 THEN 'critical' ELSE 'high' END AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(d.account_id)                                     AS account_ids,
  d.txn_ids                                               AS transaction_ids,
  d.last_ts                                               AS triggered_at,
  least(1.0, round(d.near_deposits / 6.0, 3))             AS score,
  concat('Account ', d.account_id, ' received ', cast(d.near_deposits AS STRING),
         ' sub-threshold cash deposits totalling ', cast(round(d.total_cash_in) AS STRING),
         ' ZAR within ', cast((SELECT struct_window_days FROM cfg) AS STRING),
         ' days (each below the R25k CTR limit) — structuring / smurfing signature.') AS explanation,
  map('near_deposits', cast(d.near_deposits AS STRING),
      'total_cash_in', cast(round(d.total_cash_in) AS STRING)) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM deposits d
CROSS JOIN cfg
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = d.customer_id AND em.party_type = 'customer'
WHERE d.near_deposits >= cfg.struct_min_count;
