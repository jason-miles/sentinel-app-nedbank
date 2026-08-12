-- 6.9 Geospatial "impossible travel" (marquee): consecutive card taps whose
-- implied speed (haversine km / elapsed hours) exceeds a feasible threshold.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_impossible_travel AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
ordered AS (
  SELECT card_id, account_id, txn_ts, lat, lon, city, country,
         lag(txn_ts)  OVER (PARTITION BY card_id ORDER BY txn_ts) prev_ts,
         lag(lat)     OVER (PARTITION BY card_id ORDER BY txn_ts) prev_lat,
         lag(lon)     OVER (PARTITION BY card_id ORDER BY txn_ts) prev_lon,
         lag(city)    OVER (PARTITION BY card_id ORDER BY txn_ts) prev_city
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.card_transactions
),
speeds AS (
  SELECT *,
    (2*6371*asin(sqrt(pow(sin(radians(lat-prev_lat)/2),2)
      + cos(radians(prev_lat))*cos(radians(lat))*pow(sin(radians(lon-prev_lon)/2),2))))
    / nullif((unix_timestamp(txn_ts)-unix_timestamp(prev_ts))/3600.0, 0) AS implied_kmh
  FROM ordered
  WHERE prev_ts IS NOT NULL
)
SELECT
  concat('ALRT-TRV-', s.card_id, '-', date_format(s.txn_ts,'yyyyMMddHHmm')) AS alert_id,
  'impossible_travel'                                     AS alert_type,
  'critical'                                              AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  array(s.account_id)                                     AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  s.txn_ts                                                AS triggered_at,
  least(1.0, round(s.implied_kmh / 2000.0, 3))            AS score,
  concat('Card ', s.card_id, ' tapped in ', s.prev_city, ' then ', s.city,
         ' implying ', cast(round(s.implied_kmh) AS STRING), ' km/h — physically impossible.') AS explanation,
  map('from_city', coalesce(s.prev_city,''), 'to_city', coalesce(s.city,''),
      'implied_kmh', cast(round(s.implied_kmh) AS STRING))  AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM speeds s
CROSS JOIN cfg
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a ON a.account_id = s.account_id
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = a.customer_id AND em.party_type = 'customer'
WHERE s.implied_kmh > cfg.max_feasible_kmh;
