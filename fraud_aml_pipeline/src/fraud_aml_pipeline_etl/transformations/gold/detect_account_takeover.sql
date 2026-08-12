-- 6.8 Account takeover: device/geo/credential anomaly followed by a high-value
-- debit within 1 hour.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_account_takeover AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
anomalies AS (
  SELECT ae.account_id, ae.event_ts, ae.new_device, ae.new_geo, ae.credential_change, ae.geo_city
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.auth_events ae
  WHERE ae.new_device OR ae.new_geo OR ae.credential_change
),
drains_raw AS (
  SELECT an.account_id, an.event_ts, an.geo_city,
         t.transaction_id, t.amount, t.txn_ts
  FROM anomalies an
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions t
    ON t.account_id = an.account_id
   AND t.txn_ts BETWEEN an.event_ts AND an.event_ts + INTERVAL 1 HOUR
   AND t.direction = 'debit'
  CROSS JOIN cfg
  WHERE t.amount >= cfg.ato_amount
),
-- One alert per account: keep the single largest post-anomaly drain so
-- alert_id ('ALRT-ATO-<acct>') is unique in fraud_alerts.
drains AS (
  SELECT * EXCEPT (rn) FROM (
    SELECT *, row_number() OVER (PARTITION BY account_id ORDER BY amount DESC, txn_ts DESC) rn
    FROM drains_raw
  ) WHERE rn = 1
)
SELECT
  concat('ALRT-ATO-', d.account_id)                       AS alert_id,
  'account_takeover'                                      AS alert_type,
  'critical'                                              AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(d.account_id)                                     AS account_ids,
  array(d.transaction_id)                                 AS transaction_ids,
  d.txn_ts                                                AS triggered_at,
  0.9                                                     AS score,
  concat('Auth anomaly (', coalesce(d.geo_city,'unknown geo'),
         ') followed by debit of ', cast(round(d.amount) AS STRING), ' within 1h on ', d.account_id, '.') AS explanation,
  map('geo_city', coalesce(d.geo_city,''), 'amount', cast(d.amount AS STRING)) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM drains d
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a ON a.account_id = d.account_id
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = a.customer_id AND em.party_type = 'customer';
