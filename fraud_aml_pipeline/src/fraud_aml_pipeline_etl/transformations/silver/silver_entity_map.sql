-- Silver: convenience map source_id -> entity_id, used by detection + graph.
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map (
  CONSTRAINT valid_entity_id EXPECT (entity_id IS NOT NULL),   -- WARN: the resolved-entity join key
  CONSTRAINT valid_source_id EXPECT (source_id IS NOT NULL)
) AS
SELECT source_id, party_type, entity_id, cluster_size
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entities;
