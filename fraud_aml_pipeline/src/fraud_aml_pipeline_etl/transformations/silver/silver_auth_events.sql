-- Silver passthrough: auth_events
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.auth_events (
  CONSTRAINT valid_account_id EXPECT (account_id IS NOT NULL)  -- WARN: account-takeover rule joins
) AS
SELECT * FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.auth_events;
