-- Streaming bronze: near-real-time card/tap ingestion via Auto Loader.
--
-- Card-tap feeds land as JSON files in the UC Volume
--   .../nedbank_fraud_aml_bronze/landing/card_transactions/
-- and are ingested incrementally (exactly-once) into this streaming table. This is
-- the near-real-time lane that complements the historical batch table
-- nedbank_fraud_aml_bronze.card_transactions; silver.card_transactions unions the
-- two so the impossible-travel detector (which pairs consecutive taps per card via
-- lag()) sees both feeds without any change to the detector, app, or Genie space.
CREATE OR REFRESH STREAMING TABLE
  elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.card_transactions_stream
COMMENT 'Bronze streaming — near-real-time card/tap transactions ingested from the landing volume via Auto Loader.'
AS SELECT
  card_txn_id,
  card_id,
  account_id,
  CAST(amount AS DOUBLE)                 AS amount,
  currency,
  merchant,
  merchant_category,
  channel,
  CAST(lat AS DOUBLE)                     AS lat,
  CAST(lon AS DOUBLE)                     AS lon,
  city,
  country,
  CAST(txn_ts AS TIMESTAMP)               AS txn_ts,
  current_timestamp()                     AS _ingested_at
FROM STREAM read_files(
  '/Volumes/elexon_app_for_settlement_acc_catalog/nedbank_fraud_aml_bronze/landing/card_transactions',
  format        => 'json',
  schemaHints   => 'amount DOUBLE, lat DOUBLE, lon DOUBLE, txn_ts TIMESTAMP',
  schemaEvolutionMode => 'addNewColumns'
);
