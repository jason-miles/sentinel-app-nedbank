-- Nedbank Fraud & AML — Foundation: catalog/schema/volume DDL
-- NOTE: Co-located in elexon_app_for_settlement_acc_catalog with an
-- nedbank_fraud_aml_ prefix because the workspace user lacks metastore
-- CREATE CATALOG. See README "Physical layout".

CREATE SCHEMA IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze
  COMMENT 'Nedbank Fraud & AML demo — Bronze: raw landed feeds.';

CREATE SCHEMA IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver
  COMMENT 'Nedbank Fraud & AML demo — Silver: conformed, deduplicated, entity-resolved.';

CREATE SCHEMA IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold
  COMMENT 'Nedbank Fraud & AML demo — Gold: fraud_alerts, entity_network, customer_360, alert_feedback, metric views.';

-- Volume for KYC packs, source-of-funds letters, adverse-media PDFs
-- (fed to ai_parse_document / ai_extract in the Intelligence phase).
CREATE VOLUME IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.documents
  COMMENT 'KYC packs, source-of-funds letters, adverse-media PDFs.';

-- Landing volume for the near-real-time streaming lanes (Auto Loader read_files):
--   landing/transactions/  and  landing/card_transactions/  (create both subfolders
--   with `databricks fs mkdir` before the first pipeline run — read_files needs them).
CREATE VOLUME IF NOT EXISTS elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.landing
  COMMENT 'Auto Loader landing zone for the streaming transaction + card lanes.';
