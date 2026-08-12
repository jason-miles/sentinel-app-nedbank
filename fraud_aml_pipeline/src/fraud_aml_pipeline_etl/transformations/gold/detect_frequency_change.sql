-- 6.2 Change in frequency: today's txn count deviates from the account's own
-- trailing 90-day baseline by >= freq_z standard deviations.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_frequency_change AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
daily AS (
  SELECT account_id, date(txn_ts) d, count(*) c
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions
  GROUP BY 1,2
),
baseline AS (
  SELECT account_id, avg(c) avg_c, stddev(c) std_c, count(*) AS baseline_days
  FROM daily WHERE d < current_date() GROUP BY 1
),
today AS (
  SELECT account_id, c AS today_count FROM daily WHERE d = current_date()
),
scored AS (
  SELECT t.account_id, t.today_count, b.avg_c, b.std_c, b.baseline_days,
         (t.today_count - b.avg_c) / nullif(b.std_c,0) AS z
  FROM today t JOIN baseline b USING (account_id)
)
SELECT
  concat('ALRT-FQ-', s.account_id)                        AS alert_id,
  'frequency_change'                                      AS alert_type,
  CASE WHEN coalesce(abs(s.z), 99) >= 5 THEN 'critical' ELSE 'high' END AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(s.account_id)                                     AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  current_timestamp()                                     AS triggered_at,
  least(1.0, round(coalesce(abs(s.z), 9.0)/10.0, 3))      AS score,
  concat('Account ', s.account_id, ' had ', cast(s.today_count AS STRING),
         ' txns today vs baseline avg ', cast(round(s.avg_c,1) AS STRING),
         coalesce(concat(' (z=', cast(round(s.z,2) AS STRING), ')'), ' (sparse baseline)'), '.') AS explanation,
  map('today_count', cast(s.today_count AS STRING), 'z', coalesce(cast(round(s.z,2) AS STRING), 'n/a')) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM scored s
CROSS JOIN cfg
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a ON a.account_id = s.account_id
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = a.customer_id AND em.party_type = 'customer'
-- Fire on a meaningful z-score when a real baseline stddev exists; otherwise
-- (sparse/low-variance baseline) fall back to a large multiple of the average.
WHERE (s.std_c IS NOT NULL AND s.std_c > 0 AND abs(s.z) >= cfg.freq_z)
   OR ((s.std_c IS NULL OR s.std_c = 0) AND s.today_count >= greatest(10, s.avg_c * 5));
