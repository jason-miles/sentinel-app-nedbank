-- Phase 3 Intelligence: AI-grounded adverse-media analysis (PRD §6.6).
-- Upgrades the Phase 2 name-match with ai_query summarisation: for each
-- resolved entity that matches the media corpus, generate a concise,
-- analyst-facing risk summary grounded in the actual article text.
CREATE OR REPLACE TABLE elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.adverse_media_analysis AS
WITH matches AS (
  SELECT e.entity_id, e.full_name, e.party_type,
         m.article_id, m.headline, m.body, m.source, m.published_at
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entities e
  JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.adverse_media m
    ON array_contains(m.named_entities, e.full_name)
)
SELECT
  entity_id, full_name, party_type, article_id, headline, source, published_at,
  ai_query(
    'databricks-meta-llama-3-3-70b-instruct',
    concat(
      'You are an AML analyst. In one sentence, summarise the financial-crime risk this article implies for the named party. ',
      'Party: ', full_name, '. Article: ', headline, '. ', body
    )
  ) AS risk_summary
FROM matches;
