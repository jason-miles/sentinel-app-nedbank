-- Feature 3: Behavioral peer-group anomaly detection (unsupervised).
-- Moves beyond fixed per-entity thresholds to "this customer behaves unlike its
-- peer segment." Group customers by segment, compute per-group behavioral
-- baselines (mean/stddev of 90-day txn count, total value, avg value, distinct
-- counterparties), then flag statistical outliers by z-score. Catches novel
-- typologies static rules miss and addresses the false-positive-reduction story.
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.peer_anomaly AS
WITH per_customer AS (
  SELECT
    a.customer_id,
    count(t.transaction_id)                       AS txn_count,
    coalesce(sum(t.amount),0)                      AS total_value,
    coalesce(avg(t.amount),0)                      AS avg_value,
    count(DISTINCT t.counterparty_id)              AS distinct_cps
  FROM nedbank_fraud_aml_silver.accounts a
  LEFT JOIN nedbank_fraud_aml_silver.transactions t
    ON t.account_id = a.account_id
   AND t.txn_ts >= current_timestamp() - INTERVAL 90 DAYS
  GROUP BY a.customer_id
),
feat AS (
  SELECT c.customer_id, c.full_name, c.segment, c.country,
         pc.txn_count, pc.total_value, pc.avg_value, pc.distinct_cps
  FROM nedbank_fraud_aml_silver.customers c
  JOIN per_customer pc USING (customer_id)
),
grp AS (
  SELECT segment,
         avg(txn_count) m_cnt,  stddev(txn_count) s_cnt,
         avg(total_value) m_val, stddev(total_value) s_val,
         avg(distinct_cps) m_cp, stddev(distinct_cps) s_cp
  FROM feat GROUP BY segment
),
z AS (
  SELECT f.*,
    (f.txn_count   - g.m_cnt) / nullif(g.s_cnt,0) AS z_cnt,
    (f.total_value - g.m_val) / nullif(g.s_val,0) AS z_val,
    (f.distinct_cps- g.m_cp)  / nullif(g.s_cp,0)  AS z_cp,
    g.m_cnt AS peer_avg_txns, g.m_val AS peer_avg_value
  FROM feat f JOIN grp g USING (segment)
)
SELECT
  customer_id, full_name, segment, country,
  txn_count, total_value, avg_value, distinct_cps,
  round(peer_avg_txns,1) AS peer_avg_txns, round(peer_avg_value,0) AS peer_avg_value,
  round(z_cnt,2) AS z_txn_count, round(z_val,2) AS z_total_value, round(z_cp,2) AS z_distinct_cps,
  round(greatest(abs(z_cnt), abs(z_val), abs(z_cp)),2) AS anomaly_score,
  CASE WHEN greatest(abs(z_cnt), abs(z_val), abs(z_cp)) >= 4 THEN 'critical'
       WHEN greatest(abs(z_cnt), abs(z_val), abs(z_cp)) >= 3 THEN 'high'
       ELSE 'medium' END AS severity,
  concat_ws('; ',
    CASE WHEN abs(z_cnt) >= 3 THEN concat('txn volume ', cast(round(z_cnt,1) AS STRING), 'σ from ', segment, ' peers') END,
    CASE WHEN abs(z_val) >= 3 THEN concat('total value ', cast(round(z_val,1) AS STRING), 'σ from peers') END,
    CASE WHEN abs(z_cp)  >= 3 THEN concat('counterparty count ', cast(round(z_cp,1) AS STRING), 'σ from peers') END
  ) AS explanation
FROM z
WHERE greatest(abs(z_cnt), abs(z_val), abs(z_cp)) >= 3;   -- 3σ+ outliers only
