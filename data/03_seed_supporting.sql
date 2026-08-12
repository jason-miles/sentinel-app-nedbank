-- Nedbank — Fraud & AML SAMPLE DATA · Synthetic seeder (3/4): supporting feeds
-- risk_ratings, beneficial_ownership, auth_events, adverse_media.
-- *** NEDBANK DEMO DATA — 100% SYNTHETIC ***

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── RISK RATINGS (history; baseline for risk-jump rule) ──────────────────
-- 2-3 rating rows per customer over time, mostly stable.
INSERT OVERWRITE nedbank_fraud_aml_bronze.risk_ratings
WITH cust AS (SELECT id FROM range(1, 5001)),
     hist AS (
       SELECT c.id AS cust_num, e.n AS seq
       FROM cust c LATERAL VIEW explode(sequence(1, cast(pmod(c.id,3)+2 AS INT))) e AS n
     )
SELECT
  concat('RR', lpad(cast(cust_num*10+seq AS BIGINT), 10, '0')) AS rating_id,
  concat('CUST', lpad(cust_num, 6, '0')) AS entity_id,
  'customer' AS entity_type,
  least(5, greatest(1, cast(pmod(cust_num,3)+1 AS INT) + cast(pmod(seq,2) AS INT))) AS risk_rating,
  cast(date_add('2021-01-01', cast(seq*120 + pmod(cust_num,90) AS INT)) AS TIMESTAMP) AS rated_at,
  'kyc_engine' AS rated_by,
  'periodic_review' AS reason,
  current_timestamp() AS _ingested_at
FROM hist;

-- ── BENEFICIAL OWNERSHIP (baseline; UBO-change rule) ─────────────────────
-- Company/trust third parties get a UBO pointing at another entity.
INSERT OVERWRITE nedbank_fraud_aml_bronze.beneficial_ownership
WITH tp AS (
  SELECT third_party_id,
         cast(regexp_replace(third_party_id,'^TP0*','') AS BIGINT) AS tp_num
  FROM nedbank_fraud_aml_bronze.third_parties
  WHERE entity_kind IN ('company','trust')
)
SELECT
  concat('UBO', lpad(tp_num, 10, '0')) AS ubo_id,
  third_party_id AS entity_id,
  concat('TP', lpad(cast(pmod(tp_num*7, 3000)+1 AS INT), 6, '0')) AS ubo_entity_id,
  round(pmod(tp_num*13, 60)+25, 2) AS ownership_pct,
  cast(date_add('2019-01-01', cast(pmod(tp_num*29, 2000) AS INT)) AS TIMESTAMP) AS effective_from,
  'register' AS source,
  current_timestamp() AS _ingested_at
FROM tp;

-- ── AUTH EVENTS (baseline noise; ATO planted separately) ─────────────────
-- ~5 auth events per active account, mostly benign.
INSERT OVERWRITE nedbank_fraud_aml_bronze.auth_events
WITH acct AS (
  SELECT account_id, cast(regexp_replace(account_id,'^ACC0*','') AS BIGINT) AS acct_num
  FROM nedbank_fraud_aml_bronze.accounts WHERE status='active'
),
ev AS (
  SELECT a.account_id, a.acct_num, e.n AS seq
  FROM acct a LATERAL VIEW explode(sequence(1,5)) e AS n
)
SELECT
  concat('AE', lpad(cast(acct_num*10+seq AS BIGINT), 12, '0')) AS event_id,
  account_id,
  cast(current_timestamp() - make_interval(0,0,0, cast(pmod(acct_num+seq*7,120) AS INT),0,0,0) AS TIMESTAMP) AS event_ts,
  pmod(acct_num+seq, 20)=0 AS new_device,
  pmod(acct_num+seq, 25)=0 AS new_geo,
  pmod(acct_num+seq, 40)=0 AS credential_change,
  concat('DEV', lpad(cast(pmod(acct_num*3+seq,50000) AS INT),8,'0')) AS device_id,
  concat('196.', cast(pmod(acct_num,255) AS INT), '.', cast(pmod(seq*7,255) AS INT), '.', cast(pmod(acct_num*seq,255) AS INT)) AS ip_address,
  element_at(array('Johannesburg','Cape Town','Durban','Pretoria'), cast(pmod(acct_num,4)+1 AS INT)) AS geo_city,
  current_timestamp() AS _ingested_at
FROM ev;

-- ── ADVERSE MEDIA (synthetic corpus; fictional entities) ─────────────────
INSERT OVERWRITE nedbank_fraud_aml_bronze.adverse_media
SELECT * FROM VALUES
  ('AM0001','Man named as recruiter in bank money-mule syndicate','Authorities are examining accounts connected to Onyx Capital and an individual named Sipho Dlamini in relation to a suspected money-mule network moving proceeds of online scams.', DATE'2026-05-11','News24 (synthetic)', array('Onyx Capital','Sipho Dlamini'), current_timestamp()),
  ('AM0002','Sanctions watchlist adds shell-company network','A network of nominee firms including Vanguard Nominees has been flagged for sanctions evasion.', DATE'2026-06-02','Reuters (synthetic)', array('Vanguard Nominees'), current_timestamp()),
  ('AM0003','SASSA-grant fraud suspect under investigation','Naledi Khumalo, linked to a social-grant diversion scheme, faces a fraud inquiry.', DATE'2026-06-20','Daily Maverick (synthetic)', array('Naledi Khumalo'), current_timestamp()),
  ('AM0004','Laundering ring uses layered trust structures','Investigators cite Summit Trust in a layering scheme moving illicit funds through retail accounts.', DATE'2026-07-01','Daily Maverick (synthetic)', array('Summit Trust'), current_timestamp()),
  ('AM0005','Adverse ruling against offshore vehicle','Meridian Holdings named in an offshore tax-evasion judgment.', DATE'2026-07-09','ICIJ (synthetic)', array('Meridian Holdings'), current_timestamp())
AS t(article_id, headline, body, published_at, source, named_entities, _ingested_at);
