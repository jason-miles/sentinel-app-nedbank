-- SherlockAML — sherlock_cases: one investigative case per generated alert.
-- ~650 cases over real customers across the 9 SherlockAML scenarios, with risk
-- score, priority, status, owning team/analyst, SLA due date, days open, and
-- investigation hours. Distributions echo the demo screenshots.

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE OR REPLACE TABLE nedbank_fraud_aml_gold.sherlock_cases AS
WITH base AS (
  SELECT
    id,
    -- pick a real customer to anchor each case
    concat('CUST', lpad(cast(pmod(id * 7, 5000) + 1 AS INT), 6, '0')) AS customer_id
  FROM range(1, 651)
),
scenarios AS (
  SELECT posexplode(array(
    'Rapid Fund Movement','Related Account Movement','PEP/Sanctions Alert',
    'Round Dollar Pattern','High-Risk Geography Transfer','Cash Structuring Detection',
    'Beneficiary Mismatch','Third-Party Deposit Pattern','Dormant Account Reactivation'
  )) AS (sc_idx, scenario)
),
teams AS (
  SELECT posexplode(array('TEAM_TM','TEAM_SW','TEAM_FR','TEAM_EDD')) AS (t_idx, team_id)
),
analysts AS (
  SELECT posexplode(array('AN_SARAH','AN_MICHAEL','AN_LISA','AN_MARIA','AN_NICOLE','AN_ROBERT')) AS (a_idx, analyst_id)
),
statuses AS (
  SELECT posexplode(array('new','assigned','in_progress','escalated','closed')) AS (st_idx, status)
),
priorities AS (
  SELECT posexplode(array('low','medium','medium','high','critical')) AS (p_idx, priority)
)
SELECT
  concat('CASE-', lpad(b.id, 5, '0'))                         AS case_id,
  b.id                                                        AS alert_num,
  b.customer_id,
  c.full_name                                                 AS customer_name,
  s.scenario,
  p.priority,
  st.status,
  t.team_id,
  tm.team_name,
  an.analyst_id,
  ana.analyst_name,
  -- risk score 40..99, correlated with priority
  cast(40 + pmod(b.id * 13, 55)
       + CASE p.priority WHEN 'critical' THEN 5 WHEN 'high' THEN 3 ELSE 0 END AS INT) AS risk_score,
  -- transaction amount: round-dollar scenarios get round numbers
  CASE WHEN s.scenario IN ('Round Dollar Pattern')
       THEN cast((pmod(b.id, 20) + 1) * 10000 AS DOUBLE)
       ELSE round(pmod(b.id * 9973, 9000000) + 5000, 2) END   AS amount,
  -- days open 1..140; some breach SLA
  cast(1 + pmod(b.id * 17, 140) AS INT)                       AS days_open,
  cast(date_add(current_date(), cast(30 - pmod(b.id * 11, 75) AS INT)) AS DATE) AS due_date,
  -- investigation hours 0..9, avg ~4.6
  round(pmod(b.id * 7, 90) / 10.0, 1)                         AS investigation_hours,
  cast(date_sub(current_date(), cast(1 + pmod(b.id * 17, 140) AS INT)) AS TIMESTAMP) AS opened_at
FROM base b
JOIN scenarios s  ON s.sc_idx = pmod(b.id, 9)
JOIN teams t      ON t.t_idx  = pmod(b.id, 4)
JOIN priorities p ON p.p_idx  = pmod(b.id * 3, 5)
-- NOTE: the multiplier MUST be coprime with 5, else the index collapses to a single
-- value (pmod(id*5,5) ≡ 0 pinned every case to 'new'). 7 cycles through all 5 statuses
-- so the queue, FP-rate, team-performance and resolution-flow views are all populated.
JOIN statuses st  ON st.st_idx = pmod(b.id * 7, 5)
JOIN analysts an  ON an.a_idx = pmod(b.id, 6)
LEFT JOIN nedbank_fraud_aml_gold.sherlock_teams tm ON tm.team_id = t.team_id
LEFT JOIN nedbank_fraud_aml_gold.sherlock_analysts ana ON ana.analyst_id = an.analyst_id
LEFT JOIN nedbank_fraud_aml_silver.customers c ON c.customer_id = b.customer_id;

-- ── HERO CASES for the demo "wow" narratives ─────────────────────────────
-- Anchored to the planted subjects so a demo driver can open them by name.
-- These are the cases the walkthrough (docs/nedbank_demo_walkthrough.md) drives:
--   CASE-90001  WOW-A entry: the "boring" sub-threshold structuring alert on one
--               mule (Lerato Sithole) that the copilot expands into the 7-account
--               network + cross-border cash-out.
--   CASE-90002  WOW-A aggregator: Kabelo Motaung, rapid movement + SWIFT remit.
--   CASE-90003  WOW-C: Werner Pretorius, gaming/TPP layering surfaced by the sweep.
INSERT INTO nedbank_fraud_aml_gold.sherlock_cases
  (case_id, alert_num, customer_id, customer_name, scenario, priority, status,
   team_id, team_name, analyst_id, analyst_name, risk_score, amount, days_open,
   due_date, investigation_hours, opened_at)
VALUES
  ('CASE-90001', 90001, 'CUSTMULE01', 'Lerato Sithole', 'Cash Structuring Detection', 'high', 'new',
   'TEAM_TM', 'AML Transaction Monitoring', 'AN_SARAH', 'Thandeka Nkosi', 88, 66000.00, 0,
   cast(date_add(current_date(), 2) AS DATE), 0.5, cast(current_timestamp() - INTERVAL 4 HOURS AS TIMESTAMP)),
  ('CASE-90002', 90002, 'CUSTMULE00', 'Kabelo Motaung', 'Rapid Fund Movement', 'critical', 'new',
   'TEAM_FR', 'Fraud Investigations', 'AN_MARIA', 'Anele Mbatha', 96, 280000.00, 0,
   cast(date_add(current_date(), 1) AS DATE), 0.0, cast(current_timestamp() - INTERVAL 2 HOURS AS TIMESTAMP)),
  ('CASE-90003', 90003, 'CUSTGAME01', 'Werner Pretorius', 'Third-Party Deposit Pattern', 'medium', 'new',
   'TEAM_EDD', 'Enhanced Due Diligence (EDD)', 'AN_NICOLE', 'Carel van Wyk', 74, 92000.00, 3,
   cast(date_add(current_date(), 5) AS DATE), 1.5, cast(current_timestamp() - INTERVAL 3 DAYS AS TIMESTAMP));
