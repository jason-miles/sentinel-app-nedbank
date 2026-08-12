-- 6.3 Round-trip / circular fund transactions: money returns to origin through
-- a chain of >= 3 hops. Recursive CTE over recent transfers (the SQL showcase).
-- Bounded to the last 3 days of transfers to keep recursion tractable.
CREATE OR REFRESH PRIVATE MATERIALIZED VIEW detect_circular_flow AS
WITH RECURSIVE edges AS (
  -- Bound the graph to MATERIAL transfers between distinct accounts in the last
  -- 3 days. Layering rings move material sums; this keeps recursion tractable
  -- (a full 2.4M-edge recursion is infeasible). min_transfer is a tunable floor.
  SELECT from_acct, to_acct, amount, txn_ts, transaction_id
  FROM elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.transactions
  WHERE from_acct IS NOT NULL AND to_acct IS NOT NULL AND from_acct <> to_acct
    AND txn_ts >= current_timestamp() - INTERVAL 3 DAYS
    AND amount >= 250000
),
flow (origin, current_acct, path, depth, total) AS (
  SELECT from_acct, to_acct, array(from_acct, to_acct), 1, amount
  FROM edges
  UNION ALL
  SELECT f.origin, e.to_acct, array_append(f.path, e.to_acct), f.depth + 1, f.total + e.amount
  FROM flow f
  JOIN edges e ON e.from_acct = f.current_acct
  WHERE f.depth < 5
    -- Don't revisit intermediate nodes, BUT allow the closing edge back to the
    -- origin (which is always already in the path as its first element).
    AND (NOT array_contains(f.path, e.to_acct) OR e.to_acct = f.origin)
),
rings AS (
  -- One alert per origin, preferring the SHORTEST closing ring (tightest,
  -- most legible signal — e.g. the clean 4-account loop).
  SELECT origin, path, depth, total,
         row_number() OVER (PARTITION BY origin ORDER BY depth ASC) rn
  FROM flow
  WHERE current_acct = origin AND depth >= 3
)
SELECT
  concat('ALRT-RING-', origin)                            AS alert_id,
  'circular_flow'                                         AS alert_type,
  'critical'                                              AS severity,
  em.entity_id                                            AS primary_entity_id,
  CAST(array() AS ARRAY<STRING>)                          AS related_entity_ids,
  path                                                    AS account_ids,
  CAST(array() AS ARRAY<STRING>)                          AS transaction_ids,
  current_timestamp()                                     AS triggered_at,
  0.95                                                    AS score,
  concat('Circular fund flow of ', cast(depth AS STRING), ' hops returning to ',
         origin, '; total moved ', cast(round(total) AS STRING), '.') AS explanation,
  map('path', concat_ws(' -> ', path), 'hops', cast(depth AS STRING), 'total', cast(round(total) AS STRING)) AS evidence,
  'new'                                                   AS status,
  CAST(NULL AS STRING)                                    AS analyst_feedback
FROM rings
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.accounts a ON a.account_id = rings.origin
LEFT JOIN elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_silver.entity_map em
  ON em.source_id = a.customer_id AND em.party_type = 'customer'
WHERE rn = 1;
