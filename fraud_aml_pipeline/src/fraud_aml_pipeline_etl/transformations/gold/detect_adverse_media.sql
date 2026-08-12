-- 6.6 Adverse media hits: match resolved entities against the media corpus.
-- Phase 2 uses a SQL name match against adverse_media.named_entities; Phase 3
-- (Intelligence) upgrades this to vector_search + ai_query grounding.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_adverse_media AS
WITH matches AS (
  SELECT e.entity_id, e.source_id, e.party_type, e.full_name,
         m.article_id, m.headline, m.published_at
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entities e
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.adverse_media m
    ON array_contains(m.named_entities, e.full_name)
)
SELECT
  concat('ALRT-AM-', entity_id, '-', article_id)          AS alert_id,
  'adverse_media'                                         AS alert_type,
  'high'                                                  AS severity,
  entity_id                                               AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  CAST(array() AS ARRAY<STRING>)                          AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  cast(published_at AS TIMESTAMP)                         AS triggered_at,
  0.85                                                    AS score,
  concat('Adverse media match for ', full_name, ': "', headline, '".') AS explanation,
  map('article_id', article_id, 'headline', headline)     AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM matches;
