-- 6.5 Risk-rating changes: alert on upward jumps of >= risk_jump bands.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_risk_rating_change AS
WITH cfg AS (SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.alert_config),
transitions AS (
  SELECT entity_id, entity_type, risk_rating AS new_rating, rated_at,
         lag(risk_rating) OVER (PARTITION BY entity_id ORDER BY rated_at) AS prev_rating
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.risk_ratings
)
SELECT
  concat('ALRT-RISK-', t.entity_id, '-', date_format(t.rated_at,'yyyyMMdd')) AS alert_id,
  'risk_rating_change'                                    AS alert_type,
  CASE WHEN t.new_rating >= 5 THEN 'critical' ELSE 'high' END AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  CAST(array() AS ARRAY<STRING>)                          AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  t.rated_at                                              AS triggered_at,
  least(1.0, (t.new_rating - t.prev_rating) / 5.0)        AS score,
  concat('Risk rating for ', t.entity_id, ' jumped from band ',
         cast(t.prev_rating AS STRING), ' to ', cast(t.new_rating AS STRING), '.') AS explanation,
  map('prev_rating', cast(t.prev_rating AS STRING), 'new_rating', cast(t.new_rating AS STRING)) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM transitions t
CROSS JOIN cfg
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = t.entity_id AND em.party_type = t.entity_type
WHERE t.prev_rating IS NOT NULL
  AND t.new_rating > t.prev_rating + cfg.risk_jump;
