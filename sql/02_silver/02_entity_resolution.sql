-- Nedbank Fraud & AML — Silver: ENTITY RESOLUTION (PRD §5, "the key")
-- Produce a stable entity_id spanning customers AND third parties, using:
--   * deterministic keys: national_id, tax_number
--   * fuzzy fallback: soundex(name) + city (SQL-native; ai_similarity optional)
-- The resolved entity_id is what lets us say "this customer and this third
-- party are the same beneficial owner".

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- 1) Union the two party sources into one raw party stream ----------------
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.parties_raw AS
SELECT
  customer_id       AS source_id,
  'customer'        AS party_type,
  full_name, national_id, tax_number, city, country, dob
FROM nedbank_fraud_aml_silver.customers
UNION ALL
SELECT
  third_party_id    AS source_id,
  'third_party'     AS party_type,
  full_name, national_id, tax_number, city, country, CAST(NULL AS DATE) AS dob
FROM nedbank_fraud_aml_silver.third_parties;

-- 2) Build a resolution key. Deterministic keys take precedence; where a
--    party shares national_id OR tax_number with another, they collapse to
--    the same cluster. Fuzzy fallback groups on soundex(name)+city.
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.entities AS
WITH keyed AS (
  SELECT *,
    -- deterministic cluster key: prefer national_id, else tax_number
    coalesce(nullif(national_id,''), nullif(tax_number,'')) AS det_key,
    -- fuzzy cluster key
    concat(soundex(coalesce(full_name,'')), '|', upper(coalesce(city,''))) AS fuzzy_key
  FROM nedbank_fraud_aml_silver.parties_raw
),
clustered AS (
  SELECT *,
    -- stable cluster id: deterministic key if present, otherwise fuzzy key
    coalesce(det_key, fuzzy_key) AS cluster_key
  FROM keyed
)
SELECT
  concat('ENT', lpad(cast(dense_rank() OVER (ORDER BY cluster_key) AS BIGINT), 8, '0')) AS entity_id,
  source_id,
  party_type,
  full_name, national_id, tax_number, city, country, dob,
  cluster_key,
  count(*) OVER (PARTITION BY cluster_key) AS cluster_size   -- >1 => resolved/merged
FROM clustered;

-- 3) A convenience map: source_id -> entity_id (used by detection + graph) -
CREATE OR REPLACE TABLE nedbank_fraud_aml_silver.entity_map AS
SELECT source_id, party_type, entity_id, cluster_size
FROM nedbank_fraud_aml_silver.entities;
