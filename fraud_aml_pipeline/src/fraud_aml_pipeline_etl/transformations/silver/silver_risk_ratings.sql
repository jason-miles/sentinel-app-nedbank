-- Silver passthrough: risk_ratings
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.risk_ratings (
  CONSTRAINT valid_entity_id EXPECT (entity_id IS NOT NULL),        -- WARN: lag() rule keys on it
  CONSTRAINT valid_rating    EXPECT (risk_rating BETWEEN 1 AND 5)   -- WARN: ordinal band 1..5
) AS
SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.risk_ratings;
