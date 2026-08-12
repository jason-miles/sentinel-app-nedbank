-- Gold: entity_network — edge list (source_entity_id, target_entity_id,
-- edge_type, weight, evidence) that is the substrate for the network viz and
-- ring/related-party traversal (PRD §5).
CREATE OR REFRESH MATERIALIZED VIEW elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold.entity_network AS
-- owns_account: customer -> account
SELECT
  em.entity_id                                   AS source_entity_id,
  concat('ACCT:', a.account_id)                  AS target_entity_id,
  'owns_account'                                 AS edge_type,
  1.0                                            AS weight,
  map('account_type', a.account_type)            AS evidence
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a
JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = a.customer_id AND em.party_type = 'customer'

UNION ALL
-- transacts_with: account -> counterparty (aggregated, recent)
SELECT
  concat('ACCT:', t.from_acct)                   AS source_entity_id,
  concat('ACCT:', t.to_acct)                     AS target_entity_id,
  'transacts_with'                               AS edge_type,
  cast(count(*) AS DOUBLE)                        AS weight,
  map('total_amount', cast(round(sum(t.amount)) AS STRING)) AS evidence
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions t
WHERE t.from_acct IS NOT NULL AND t.to_acct IS NOT NULL AND t.from_acct <> t.to_acct
  AND t.txn_ts >= current_timestamp() - INTERVAL 30 DAYS
GROUP BY t.from_acct, t.to_acct

UNION ALL
-- beneficial_owner: entity -> ubo
SELECT
  em.entity_id                                   AS source_entity_id,
  coalesce(em2.entity_id, bo.ubo_entity_id)      AS target_entity_id,
  'beneficial_owner'                             AS edge_type,
  bo.ownership_pct / 100.0                        AS weight,
  map('effective_from', cast(bo.effective_from AS STRING)) AS evidence
FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.beneficial_ownership bo
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = bo.entity_id AND em.party_type = 'third_party'
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em2
  ON em2.source_id = bo.ubo_entity_id AND em2.party_type = 'third_party';
