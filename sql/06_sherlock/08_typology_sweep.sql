-- Feature: RETROSPECTIVE TYPOLOGY SWEEP (demo "wow" scenario C).
-- The proactive moment: a compliance manager asks "a new FATF typology was just
-- published on third-party payment processors layering through gaming merchants —
-- do we have exposure?" This view answers it by pattern, NOT by a pre-existing rule.
-- It surfaces accounts whose merchant-category behaviour matches the typology but
-- that never tripped an amount/velocity rule (i.e. absent from gold.fraud_alerts).
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- Per-account exposure to the gaming / third-party-payment-processor layering
-- typology: matched debits out to a gaming/TPP merchant and near-equal credits back.
CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.typology_exposure AS
WITH gaming AS (
  SELECT a.customer_id, t.account_id,
         sum(CASE WHEN t.direction='debit'  THEN t.amount ELSE 0 END) AS gaming_out,
         sum(CASE WHEN t.direction='credit' THEN t.amount ELSE 0 END) AS gaming_in,
         count(*) AS gaming_txns
  FROM nedbank_fraud_aml_silver.transactions t
  JOIN nedbank_fraud_aml_silver.accounts a USING (account_id)
  WHERE t.merchant_category = 'gaming'
  GROUP BY a.customer_id, t.account_id
),
-- accounts that DID trip a legacy rule (so we can highlight the ones that did NOT)
alerted AS (
  SELECT DISTINCT em.source_id AS customer_id
  FROM nedbank_fraud_aml_gold.fraud_alerts fa
  JOIN nedbank_fraud_aml_silver.entity_map em
    ON em.entity_id = fa.primary_entity_id AND em.party_type = 'customer'
)
SELECT
  'tpp_gaming_layering'                                   AS typology,
  g.customer_id, g.account_id, c.full_name, c.segment,
  c.declared_monthly_turnover,
  round(g.gaming_out, 2)                                  AS gaming_out,
  round(g.gaming_in, 2)                                   AS gaming_in,
  g.gaming_txns,
  -- net flow near zero + high round-trip ratio = classic layering signature
  round(g.gaming_in / nullif(g.gaming_out, 0), 3)         AS roundtrip_ratio,
  round(abs(g.gaming_out - g.gaming_in), 2)               AS net_flow,
  (al.customer_id IS NULL)                                AS never_alerted,
  concat('Round-tripped ', cast(round(g.gaming_out) AS STRING),
         ' ZAR out / ', cast(round(g.gaming_in) AS STRING),
         ' ZAR back through a gaming/TPP merchant across ',
         cast(g.gaming_txns AS STRING), ' transactions',
         CASE WHEN al.customer_id IS NULL
              THEN ' — never triggered a monitoring rule.' ELSE '.' END) AS explanation
FROM gaming g
JOIN nedbank_fraud_aml_silver.customers c ON c.customer_id = g.customer_id
LEFT JOIN alerted al ON al.customer_id = g.customer_id
WHERE g.gaming_txns >= 10
  AND g.gaming_in / nullif(g.gaming_out, 0) >= 0.8   -- near-equal round trip
ORDER BY g.gaming_out DESC;
