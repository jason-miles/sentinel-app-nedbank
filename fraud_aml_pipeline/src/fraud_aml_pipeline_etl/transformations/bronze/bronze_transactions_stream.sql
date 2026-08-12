-- Streaming bronze: near-real-time transaction ingestion via Auto Loader.
--
-- New transaction feeds land as JSON files in the UC Volume
--   elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.landing/transactions/
-- and are ingested incrementally (exactly-once) into this streaming table. This is
-- the near-real-time lane that complements the historical batch table
-- nedbank_fraud_aml_bronze.transactions (2.4M seeded rows); silver.transactions
-- unions the two so detection sees both without any change to the detectors, app,
-- or Genie space.
--
-- read_files/Auto Loader gives incremental file discovery + schema inference with
-- rescue, so a malformed drop never fails the stream.
CREATE OR REFRESH STREAMING TABLE
  elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.transactions_stream
COMMENT 'Bronze streaming — near-real-time ledger transactions ingested from the landing volume via Auto Loader.'
AS SELECT
  transaction_id,
  account_id,
  from_acct,
  to_acct,
  direction,
  CAST(amount AS DOUBLE)                 AS amount,
  currency,
  counterparty_id,
  channel,
  merchant_category,
  CAST(txn_ts AS TIMESTAMP)              AS txn_ts,
  description,
  device_id,
  ip_address,
  CAST(is_cross_border AS BOOLEAN)       AS is_cross_border,
  source_system,
  current_timestamp()                    AS _ingested_at
FROM STREAM read_files(
  '/Volumes/elexon_app_for_settlement_acc_catalog/nedbank_fraud_aml_bronze/landing/transactions',
  format        => 'json',
  schemaHints   => 'amount DOUBLE, txn_ts TIMESTAMP, is_cross_border BOOLEAN',
  schemaEvolutionMode => 'addNewColumns'
);
