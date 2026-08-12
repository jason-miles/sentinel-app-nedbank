-- Silver conform: card_transactions — unions the historical batch feed with the
-- near-real-time streaming feed, then dedupes to the latest ingest per card_txn_id.
--
--  * bronze.card_transactions        — seeded rows (static batch source; read by
--                                      fully-qualified name, no dep edge needed).
--  * card_transactions_stream        — Auto Loader streaming table in this pipeline,
--                                      referenced by its published FQN so Lakeflow
--                                      builds a real dependency edge and orders it
--                                      before this MV (same hot-path fix as
--                                      silver.transactions).
--
-- The impossible-travel detector, app, and Genie space read this table by name, so
-- streamed taps flow through to alerts with zero downstream changes.
CREATE OR REFRESH MATERIALIZED VIEW
  elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.card_transactions (
  CONSTRAINT valid_card_txn_id EXPECT (card_txn_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT valid_amount      EXPECT (amount IS NOT NULL AND amount >= 0)
) AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY card_txn_id ORDER BY _ingested_at DESC) rn
  FROM (
    SELECT card_txn_id, card_id, account_id, amount, currency, merchant, merchant_category,
           channel, lat, lon, city, country, txn_ts, _ingested_at
    FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.card_transactions
    UNION ALL
    SELECT card_txn_id, card_id, account_id, amount, currency, merchant, merchant_category,
           channel, lat, lon, city, country, txn_ts, _ingested_at
    FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.card_transactions_stream
  )
) WHERE rn = 1;
