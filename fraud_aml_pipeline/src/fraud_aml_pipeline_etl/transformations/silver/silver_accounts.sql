-- Silver conform: accounts (dedupe latest ingest per account_id)
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts (
  -- WARN (not DROP ROW): records the DQ metric without dropping rows that downstream
  -- detectors/ER join on — a dropped account would silently break those joins.
  CONSTRAINT valid_account_id EXPECT (account_id IS NOT NULL)
) AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY account_id ORDER BY _ingested_at DESC) rn
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.accounts
) WHERE rn = 1;
