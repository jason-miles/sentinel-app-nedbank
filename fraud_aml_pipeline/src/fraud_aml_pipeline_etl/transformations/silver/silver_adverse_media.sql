-- Silver passthrough: adverse_media
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.adverse_media (
  CONSTRAINT valid_article_id EXPECT (article_id IS NOT NULL) ON VIOLATION DROP ROW  -- VS index pk
) AS
SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.adverse_media;
