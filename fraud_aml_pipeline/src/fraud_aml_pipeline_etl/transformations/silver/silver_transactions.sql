-- Silver conform: transactions — unions the historical batch feed with the
-- near-real-time streaming feed, then dedupes to the latest ingest per
-- transaction_id.
--
--  * bronze.transactions        — 2.4M seeded rows (static batch source; read by
--                                 fully-qualified name, no dependency edge needed).
--  * transactions_stream        — Auto Loader streaming table in this pipeline,
--                                 published to the bronze schema. Referenced by its
--                                 fully-qualified published name: under Lakeflow's
--                                 default (multi-schema) publishing this resolves to
--                                 the in-pipeline dataset and builds a dependency
--                                 edge, so the stream is ordered before this MV.
--
-- Detectors, the app, and the Genie space all read this table by name, so new
-- streamed transactions flow through to alerts with zero downstream changes.
CREATE OR REFRESH MATERIALIZED VIEW
  elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions (
  CONSTRAINT valid_txn_id  EXPECT (transaction_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_amount  EXPECT (amount IS NOT NULL AND amount >= 0)
) AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY transaction_id ORDER BY _ingested_at DESC) rn
  FROM (
    SELECT transaction_id, account_id, from_acct, to_acct, direction, amount,
           currency, counterparty_id, channel, merchant_category, txn_ts, description,
           device_id, ip_address, is_cross_border, source_system, _ingested_at
    FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.transactions
    UNION ALL
    SELECT transaction_id, account_id, from_acct, to_acct, direction, amount,
           currency, counterparty_id, channel, merchant_category, txn_ts, description,
           device_id, ip_address, is_cross_border, source_system, _ingested_at
    FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.transactions_stream
  )
) WHERE rn = 1;
