-- Feature 2: Perpetual KYC (pKYC) — dynamic, continuously-recomputed customer
-- risk rating. Replaces the static risk_rating with a living 0-100 score built
-- from live signals: open alerts, sanctions/watchlist hits, adverse media,
-- high-risk geography exposure, dormancy, and balance/velocity. Crossing a band
-- triggers an EDD (Enhanced Due Diligence) review.
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE OR REPLACE VIEW nedbank_fraud_aml_gold.pkyc_customer_risk AS
WITH cust AS (
  SELECT c.customer_id, c.full_name, c.segment, c.city, c.country, em.entity_id,
         c.declared_monthly_turnover, c.declared_occupation, c.pep_flag, c.kyc_tier
  FROM nedbank_fraud_aml_silver.customers c
  LEFT JOIN nedbank_fraud_aml_silver.entity_map em
    ON em.source_id = c.customer_id AND em.party_type = 'customer'
),
-- Actual-vs-declared: the flagship AML signal. Sum the last 30 days of credit
-- throughput per customer and compare against the turnover they declared at KYC.
turnover_sig AS (
  SELECT a.customer_id,
         sum(CASE WHEN t.direction='credit' THEN t.amount ELSE 0 END) AS actual_monthly_turnover
  FROM nedbank_fraud_aml_silver.transactions t
  JOIN nedbank_fraud_aml_silver.accounts a USING (account_id)
  WHERE t.txn_ts >= current_timestamp() - INTERVAL 30 DAYS
  GROUP BY a.customer_id
),
alert_sig AS (
  SELECT em.source_id AS customer_id,
         count(*) AS alert_count,
         sum(CASE WHEN fa.severity IN ('critical','high') THEN 1 ELSE 0 END) AS severe_alerts
  FROM nedbank_fraud_aml_gold.fraud_alerts fa
  JOIN nedbank_fraud_aml_silver.entity_map em
    ON em.entity_id = fa.primary_entity_id AND em.party_type = 'customer'
  GROUP BY em.source_id
),
sanc_sig AS (
  SELECT source_id AS customer_id, max(match_score) AS top_sanction, count(*) AS sanction_hits
  FROM nedbank_fraud_aml_gold.sanctions_screening_hits
  WHERE party_type = 'customer'
  GROUP BY source_id
),
media_sig AS (
  SELECT em.source_id AS customer_id, count(*) AS media_hits
  FROM nedbank_fraud_aml_gold.adverse_media_analysis am
  JOIN nedbank_fraud_aml_silver.entity_map em
    ON em.entity_id = am.entity_id AND em.party_type = 'customer'
  GROUP BY em.source_id
),
acct_sig AS (
  SELECT customer_id, sum(balance) AS total_balance,
         max(CASE WHEN status='dormant' THEN 1 ELSE 0 END) AS has_dormant
  FROM nedbank_fraud_aml_silver.accounts GROUP BY customer_id
),
scored AS (
  SELECT
    cu.customer_id, cu.full_name, cu.segment, cu.city, cu.country, cu.entity_id,
    cu.declared_occupation, cu.pep_flag, cu.kyc_tier,
    coalesce(cu.declared_monthly_turnover,0) AS declared_monthly_turnover,
    coalesce(ts.actual_monthly_turnover,0)   AS actual_monthly_turnover,
    -- how many times over the declared expectation the actual throughput runs
    round(coalesce(ts.actual_monthly_turnover,0)
          / nullif(cu.declared_monthly_turnover,0), 1) AS turnover_ratio,
    coalesce(a.alert_count,0) AS alert_count,
    coalesce(a.severe_alerts,0) AS severe_alerts,
    coalesce(s.sanction_hits,0) AS sanction_hits,
    coalesce(m.media_hits,0) AS media_hits,
    coalesce(ac.total_balance,0) AS total_balance,
    coalesce(ac.has_dormant,0) AS has_dormant,
    -- component weights -> 0-100 dynamic risk
    least(100,
        coalesce(a.severe_alerts,0) * 12
      + (coalesce(a.alert_count,0) - coalesce(a.severe_alerts,0)) * 5
      + CASE WHEN coalesce(s.sanction_hits,0) > 0 THEN 40 ELSE 0 END
      + coalesce(m.media_hits,0) * 8
      + CASE WHEN cu.country IN ('UAE','Mauritius','United Kingdom') AND cu.country <> 'South Africa' THEN 8 ELSE 0 END
      + CASE WHEN coalesce(ac.has_dormant,0) = 1 THEN 6 ELSE 0 END
      + CASE WHEN coalesce(ac.total_balance,0) > 5000000 THEN 6 ELSE 0 END
      -- actual-vs-declared turnover breach: the flagship CDD signal
      + CASE WHEN cu.declared_monthly_turnover > 0
                  AND coalesce(ts.actual_monthly_turnover,0) >= 3 * cu.declared_monthly_turnover THEN 20
             WHEN cu.declared_monthly_turnover > 0
                  AND coalesce(ts.actual_monthly_turnover,0) >= 1.5 * cu.declared_monthly_turnover THEN 8
             ELSE 0 END
      + CASE WHEN cu.pep_flag THEN 10 ELSE 0 END
    ) AS dynamic_risk
  FROM cust cu
  LEFT JOIN turnover_sig ts ON ts.customer_id = cu.customer_id
  LEFT JOIN alert_sig a  ON a.customer_id = cu.customer_id
  LEFT JOIN sanc_sig s   ON s.customer_id = cu.customer_id
  LEFT JOIN media_sig m  ON m.customer_id = cu.customer_id
  LEFT JOIN acct_sig ac  ON ac.customer_id = cu.customer_id
)
SELECT *,
  CASE WHEN dynamic_risk >= 70 THEN 'critical'
       WHEN dynamic_risk >= 45 THEN 'high'
       WHEN dynamic_risk >= 20 THEN 'medium'
       ELSE 'low' END AS risk_band,
  (dynamic_risk >= 45) AS edd_review_required,
  concat_ws('; ',
    CASE WHEN severe_alerts > 0 THEN concat(cast(severe_alerts AS STRING),' severe alerts') END,
    CASE WHEN sanction_hits > 0 THEN 'sanctions/watchlist hit' END,
    CASE WHEN media_hits > 0 THEN concat(cast(media_hits AS STRING),' adverse-media hits') END,
    CASE WHEN declared_monthly_turnover > 0 AND turnover_ratio >= 1.5
         THEN concat('turnover ', cast(turnover_ratio AS STRING), 'x declared') END,
    CASE WHEN pep_flag THEN 'PEP' END,
    CASE WHEN has_dormant = 1 THEN 'dormant account' END,
    CASE WHEN total_balance > 5000000 THEN 'high balance exposure' END
  ) AS risk_drivers
FROM scored;
