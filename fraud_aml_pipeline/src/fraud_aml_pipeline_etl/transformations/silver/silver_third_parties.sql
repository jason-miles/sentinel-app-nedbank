-- Silver conform: third_parties (dedupe latest ingest per third_party_id)
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.third_parties (
  CONSTRAINT valid_third_party_id EXPECT (third_party_id IS NOT NULL)  -- WARN: ER + counterparty joins
) AS
SELECT * EXCEPT (rn) FROM (
  SELECT *, row_number() OVER (PARTITION BY third_party_id ORDER BY _ingested_at DESC) rn
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_bronze.third_parties
) WHERE rn = 1;
