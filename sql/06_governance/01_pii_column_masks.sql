-- Nedbank Sentinel — bank-grade governance: PII column masking (NEXT_STEPS #5).
--
-- Unity Catalog column-mask functions applied to PII on the bronze master tables.
-- Masked BY DEFAULT for everyone; only members of the `aml_pii_reviewers` account
-- group see cleartext. Because the mask lives in UC, it applies uniformly to the
-- app, Genie, and any ad-hoc SQL — not just the application layer.
--
-- IMPORTANT — entity-resolution keys are deliberately NOT masked:
--   silver_entities resolves parties on national_id / tax_number (deterministic ER
--   keys). Masking those would collapse entity resolution. In production those would
--   be TOKENISED AT INGEST (format-preserving) so ER still works on the token while
--   the raw value never lands — out of scope for this demo. Here we mask the pure-PII
--   columns that are not join keys: email, phone, dob, address.
--
-- Run against the setup warehouse (functions live in the gold schema so the app SP,
-- which already has USE on it, can resolve them).

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── Mask functions ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION nedbank_fraud_aml_gold.mask_email(v STRING)
RETURN CASE WHEN is_account_group_member('aml_pii_reviewers') THEN v
            WHEN v IS NULL THEN NULL
            ELSE regexp_replace(v, '^[^@]+', '****') END;

CREATE OR REPLACE FUNCTION nedbank_fraud_aml_gold.mask_phone(v STRING)
RETURN CASE WHEN is_account_group_member('aml_pii_reviewers') THEN v
            WHEN v IS NULL THEN NULL
            ELSE concat('*******', right(v, 3)) END;

CREATE OR REPLACE FUNCTION nedbank_fraud_aml_gold.mask_dob(v DATE)
RETURN CASE WHEN is_account_group_member('aml_pii_reviewers') THEN v
            WHEN v IS NULL THEN NULL
            ELSE date_trunc('YEAR', v) END;

CREATE OR REPLACE FUNCTION nedbank_fraud_aml_gold.mask_addr(v STRING)
RETURN CASE WHEN is_account_group_member('aml_pii_reviewers') THEN v
            WHEN v IS NULL THEN NULL
            ELSE '*** REDACTED ***' END;

-- ── Apply masks ─────────────────────────────────────────────────────────────
ALTER TABLE nedbank_fraud_aml_bronze.customers
  ALTER COLUMN email   SET MASK nedbank_fraud_aml_gold.mask_email;
ALTER TABLE nedbank_fraud_aml_bronze.customers
  ALTER COLUMN phone   SET MASK nedbank_fraud_aml_gold.mask_phone;
ALTER TABLE nedbank_fraud_aml_bronze.customers
  ALTER COLUMN dob     SET MASK nedbank_fraud_aml_gold.mask_dob;
ALTER TABLE nedbank_fraud_aml_bronze.customers
  ALTER COLUMN address SET MASK nedbank_fraud_aml_gold.mask_addr;

ALTER TABLE nedbank_fraud_aml_bronze.third_parties
  ALTER COLUMN address SET MASK nedbank_fraud_aml_gold.mask_addr;

-- To grant a steward cleartext access:
--   (account admin) add the user to the `aml_pii_reviewers` account group.
-- To remove a mask:  ALTER TABLE ... ALTER COLUMN <c> DROP MASK;
