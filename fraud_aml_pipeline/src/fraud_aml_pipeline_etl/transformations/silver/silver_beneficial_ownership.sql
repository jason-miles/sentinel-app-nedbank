-- Silver passthrough: beneficial_ownership
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.beneficial_ownership (
  CONSTRAINT valid_entity_id EXPECT (entity_id IS NOT NULL),        -- WARN: UBO-change rule keys
  CONSTRAINT valid_ownership EXPECT (ownership_pct IS NULL OR (ownership_pct >= 0 AND ownership_pct <= 100))
) AS
SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.beneficial_ownership;
