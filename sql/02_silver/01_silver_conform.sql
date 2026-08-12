-- Nedbank Fraud & AML — Silver layer: conform, dedupe, resolve
-- In production this is a Lakeflow Declarative Pipeline (SQL). For the demo we
-- materialize the same logic as Delta tables so the app + detection rules read
-- stable objects. Data-Vault <-> Tabular conflicts are reconciled here.
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── Conformed CUSTOMERS (dedupe on customer_id, latest ingest wins) ───────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.customers AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY customer_id ORDER BY _ingested_at DESC) rn
  FROM nedbank_fraud_aml_bronze.customers
) WHERE rn = 1;

-- ── Conformed THIRD PARTIES ──────────────────────────────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.third_parties AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY third_party_id ORDER BY _ingested_at DESC) rn
  FROM nedbank_fraud_aml_bronze.third_parties
) WHERE rn = 1;

-- ── Conformed ACCOUNTS ───────────────────────────────────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.accounts AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY account_id ORDER BY _ingested_at DESC) rn
  FROM nedbank_fraud_aml_bronze.accounts
) WHERE rn = 1;

-- ── Conformed TRANSACTIONS (dedupe on transaction_id) ────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.transactions AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY transaction_id ORDER BY _ingested_at DESC) rn
  FROM nedbank_fraud_aml_bronze.transactions
) WHERE rn = 1;

-- ── Conformed CARD TRANSACTIONS ──────────────────────────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.card_transactions AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY card_txn_id ORDER BY _ingested_at DESC) rn
  FROM nedbank_fraud_aml_bronze.card_transactions
) WHERE rn = 1;

-- ── Pass-throughs for supporting feeds ───────────────────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.risk_ratings AS
SELECT * FROM nedbank_fraud_aml_bronze.risk_ratings;

CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.beneficial_ownership AS
SELECT * FROM nedbank_fraud_aml_bronze.beneficial_ownership;

CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.auth_events AS
SELECT * FROM nedbank_fraud_aml_bronze.auth_events;

CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.adverse_media AS
SELECT * FROM nedbank_fraud_aml_bronze.adverse_media;
