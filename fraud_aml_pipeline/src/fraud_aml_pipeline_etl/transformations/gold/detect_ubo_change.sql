-- 6.7 Beneficial ownership changes: detect UBO transitions in the register.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_ubo_change AS
WITH transitions AS (
  SELECT entity_id, ubo_entity_id AS new_ubo, effective_from,
         lag(ubo_entity_id) OVER (PARTITION BY entity_id ORDER BY effective_from) AS prev_ubo
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.beneficial_ownership
)
SELECT
  concat('ALRT-UBO-', t.entity_id, '-', date_format(t.effective_from,'yyyyMMdd')) AS alert_id,
  'ubo_change'                                            AS alert_type,
  'high'                                                  AS severity,
  em.entity_id                                            AS primary_entity_id,
  array(t.new_ubo)                                        AS related_entity_ids,
  CAST(array() AS ARRAY<STRING>)                          AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  t.effective_from                                        AS triggered_at,
  0.75                                                    AS score,
  concat('Beneficial owner of ', t.entity_id, ' changed from ',
         coalesce(t.prev_ubo,'(none)'), ' to ', t.new_ubo, '.') AS explanation,
  map('prev_ubo', coalesce(t.prev_ubo,''), 'new_ubo', t.new_ubo) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM transitions t
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = t.entity_id AND em.party_type = 'third_party'
-- Only actual UBO changes (not every first-ever record, which would be noise).
WHERE t.prev_ubo IS NOT NULL AND t.new_ubo <> t.prev_ubo;
