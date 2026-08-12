-- Nedbank — Fraud & AML SAMPLE DATA · Synthetic seeder (4/4): PLANTED SCENARIOS
-- *** NEDBANK DEMO DATA — 100% SYNTHETIC, NO REAL CLIENTS ***
-- Guarantees every alert family fires on demo day (PRD §10) AND authors the three
-- "wow" narratives from the app-building brief as discoverable ground truth.
-- All planted IDs use a FRAUD_ / MULE / GAME / DUP prefix so they are easy to trace.
-- Every name is obviously synthetic; subject mailboxes use @demo.nedbank.co.za.
--
-- Nedbank framing: the headline typology is a MONEY-MULE / LAUNDERING NETWORK
-- operating through ordinary Nedbank retail accounts — the dominant financial-
-- crime pattern for a mass-market bank (recruited mules, sub-threshold cash-ins,
-- rapid pass-through, cross-border cash-out). Amounts are set above the AML
-- detection thresholds in gold_alert_config.sql so every rule fires on demo day.
--
-- Legacy detection families (fire individually):
--   A. Rapid movement of funds (mule pass-through)         -> rule 6.1
--   B. Change in frequency (velocity spike)                -> rule 6.2
--   C. Round-trip / circular ring (4 accounts)             -> rule 6.3
--   D. Dormant reactivation with high value (5 cases)      -> rule 6.4
--   E. Risk-rating jump                                    -> rule 6.5
--   F. Adverse-media hit (entity matches media corpus)     -> rule 6.6
--   G. Beneficial-ownership change                         -> rule 6.7
--   H. Account-takeover sequence                           -> rule 6.8
--   I. Impossible travel (3 cards, JHB -> London 30 min)   -> rule 6.9
--   J. Cash structuring (sub-threshold cash deposits)      -> rule 6.10  (NEW)
--
-- Demo "wow" scenarios (composite narratives on top of the families):
--   WOW-A: the hidden 7-account mule network (structuring + rapid movement +
--          shared device/IP/address ER cluster + cross-border cash-out, with
--          3 sibling accounts previously closed as false positives).
--   WOW-B: SAR drafted + goAML in 90s (driven by the app's SAR agent — no data).
--   WOW-C: retrospective FATF sweep — third-party payment processors layering
--          through GAMING merchants; accounts that never tripped a rule.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ═══════════════════════════════════════════════════════════════════════════
-- Dedicated fraud customers + accounts + third parties (legacy families A–I)
-- ═══════════════════════════════════════════════════════════════════════════
-- Synthetic subjects on Nedbank retail accounts.
INSERT INTO nedbank_fraud_aml_bronze.customers
  (customer_id, full_name, dob, national_id, tax_number, email, phone, address, city, country,
   segment, kyc_tier, declared_occupation, declared_monthly_turnover, pep_flag, employer_name,
   device_id, onboarded_at, onboarding_channel, source_system, _ingested_at)
VALUES
  ('CUSTFRAUD01','Sipho Dlamini', DATE'1990-03-12','ID7000000001','TAX700000001','sdlamini@demo.nedbank.co.za','+27820000001','14 Vilakazi St','Soweto','South Africa','migoals_plus','tier2','Small trader', 20000.0, false,'Self','DEVFRAUD0001', TIMESTAMP'2020-01-05 09:00:00','branch','crm', current_timestamp()),
  ('CUSTFRAUD02','Naledi Khumalo', DATE'1995-08-22','ID7000000002','TAX700000002','nkhumalo@demo.nedbank.co.za','+27820000002','27 Klipfontein Rd','Mitchells Plain','South Africa','pay_as_you_use','tier1','Retail worker', 12000.0, false,'Shoprite Holdings','DEVFRAUD0002', TIMESTAMP'2019-06-15 09:00:00','app','crm', current_timestamp()),
  ('CUSTFRAUD03','Bongani Zulu', DATE'1988-11-02','ID7000000003','TAX700000003','bzulu@demo.nedbank.co.za','+27820000003','3 Govan Mbeki Ave','Mthatha','South Africa','migoals_plus','tier2','Driver', 15000.0, false,'Self','DEVFRAUD0003', TIMESTAMP'2018-02-20 09:00:00','branch','crm', current_timestamp()),
  ('CUSTFRAUD04','Chloe Adams', DATE'1993-05-30','ID7000000004','TAX700000004','cadams@demo.nedbank.co.za','+27820000004','41 Church St','Bloemfontein','South Africa','migoals_premium','tier2','Self-employed', 40000.0, false,'Self','DEVFRAUD0004', TIMESTAMP'2021-09-01 09:00:00','app','crm', current_timestamp()),
  ('CUSTFRAUD05','Thabo Mokoena', DATE'1985-01-19','ID7000000005','TAX700000005','tmokoena@demo.nedbank.co.za','+27820000005','5 Main St','Polokwane','South Africa','business','tier3','Self-employed', 60000.0, true,'Self','DEVFRAUD0005', TIMESTAMP'2020-07-11 09:00:00','branch','crm', current_timestamp());

-- Ring + passthrough + travel accounts (fixed IDs) ------------------------
INSERT INTO nedbank_fraud_aml_bronze.accounts VALUES
  ('ACCFRAUD01','CUSTFRAUD01','migoals_transact','ZAR', TIMESTAMP'2020-01-06 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 82000.00,'crm', current_timestamp()),
  ('ACCFRAUD02','CUSTFRAUD02','migoals_transact','ZAR', TIMESTAMP'2019-06-16 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 54000.00,'crm', current_timestamp()),
  ('ACCFRAUD03','CUSTFRAUD03','migoals_transact','ZAR', TIMESTAMP'2018-02-21 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 31000.00,'crm', current_timestamp()),
  ('ACCFRAUD04','CUSTFRAUD04','migoals_transact','ZAR', TIMESTAMP'2021-09-02 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 27500.00,'crm', current_timestamp()),
  -- passthrough (rapid movement) mule account
  ('ACCFRAUD05','CUSTFRAUD05','migoals_transact','ZAR', TIMESTAMP'2020-07-12 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 9000.00,'crm', current_timestamp()),
  -- card account for impossible travel (3 cards belong to 3 fraud customers)
  ('ACCFRAUDC1','CUSTFRAUD01','card','ZAR', TIMESTAMP'2020-01-06 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 12000.00,'crm', current_timestamp()),
  ('ACCFRAUDC2','CUSTFRAUD02','card','ZAR', TIMESTAMP'2019-06-16 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 9000.00,'crm', current_timestamp()),
  ('ACCFRAUDC3','CUSTFRAUD03','card','ZAR', TIMESTAMP'2018-02-21 09:00:00','active', cast(date_sub(current_date(),1) AS TIMESTAMP), 6000.00,'crm', current_timestamp()),
  -- 5 dormant savings pockets to be reactivated
  ('ACCDORM01','CUSTFRAUD01','savings_pocket','ZAR', TIMESTAMP'2019-01-01 09:00:00','dormant', cast(date_sub(current_date(),300) AS TIMESTAMP), 15000.00,'crm', current_timestamp()),
  ('ACCDORM02','CUSTFRAUD02','savings_pocket','ZAR', TIMESTAMP'2019-01-01 09:00:00','dormant', cast(date_sub(current_date(),365) AS TIMESTAMP), 22000.00,'crm', current_timestamp()),
  ('ACCDORM03','CUSTFRAUD03','savings_pocket','ZAR', TIMESTAMP'2019-01-01 09:00:00','dormant', cast(date_sub(current_date(),400) AS TIMESTAMP), 18000.00,'crm', current_timestamp()),
  ('ACCDORM04','CUSTFRAUD04','savings_pocket','ZAR', TIMESTAMP'2019-01-01 09:00:00','dormant', cast(date_sub(current_date(),250) AS TIMESTAMP), 9500.00,'crm', current_timestamp()),
  ('ACCDORM05','CUSTFRAUD05','savings_pocket','ZAR', TIMESTAMP'2019-01-01 09:00:00','dormant', cast(date_sub(current_date(),210) AS TIMESTAMP), 30000.00,'crm', current_timestamp()),
  -- ATO target account
  ('ACCATO01','CUSTFRAUD04','migoals_transact','ZAR', TIMESTAMP'2021-09-02 09:00:00','active', cast(date_sub(current_date(),2) AS TIMESTAMP), 41000.00,'crm', current_timestamp());

-- Adverse-media / UBO third party (matches adverse_media corpus) ----------
-- NOTE: TPFRAUD01/02 deliberately SHARE the national_id + tax_number of
-- CUSTFRAUD01 (Sipho Dlamini) and CUSTFRAUD02 (Naledi Khumalo) respectively, so
-- silver entity resolution collapses each customer+third-party pair into one
-- entity_id — proving the PRD's "same beneficial owner" ontology point.
INSERT INTO nedbank_fraud_aml_bronze.third_parties VALUES
  ('TPFRAUD01','Onyx Capital','company','ID7000000001','TAX700000001','9 Offshore Rd','Ebene','Mauritius', TIMESTAMP'2017-01-01 09:00:00','register', current_timestamp()),
  ('TPFRAUD02','Vanguard Nominees','company','ID7000000002','TAX700000002','10 Nominee Rd','Dubai','UAE', TIMESTAMP'2016-05-01 09:00:00','register', current_timestamp()),
  ('TPFRAUD03','Summit Trust','trust','ID7100000003','TAX710000003','11 Trust Ln','London','United Kingdom', TIMESTAMP'2015-03-01 09:00:00','register', current_timestamp());

-- Column lists reused by the transaction INSERTs below.
-- transactions: (transaction_id, account_id, from_acct, to_acct, direction, amount,
--   currency, counterparty_id, channel, merchant_category, txn_ts, description,
--   device_id, ip_address, is_cross_border, source_system, _ingested_at)

-- ── A. RAPID MOVEMENT OF FUNDS (passthrough within 24h) ──────────────────
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
VALUES
  ('TXNFRAUDA1','ACCFRAUD05','ACCFRAUD01','ACCFRAUD05','credit', 4000000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 6 HOURS AS TIMESTAMP),'Inbound transfer','DEVFRAUD0005','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNFRAUDA2','ACCFRAUD05','ACCFRAUD05','ACCFRAUD02','debit', 3850000.00,'ZAR','TPFRAUD02','swift','transfer', cast(current_timestamp() - INTERVAL 2 HOURS AS TIMESTAMP),'Outbound SWIFT remittance','DEVFRAUD0005','102.65.10.4', true,'ledger', current_timestamp());

-- ── B. CHANGE IN FREQUENCY (velocity spike today) ────────────────────────
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
SELECT concat('TXNFRAUDB', lpad(n,3,'0')), 'ACCFRAUD01', 'ACCFRAUD01',
       concat('ACC', lpad(cast(pmod(n*17,125000)+1 AS BIGINT),8,'0')), 'debit',
       round(50000 + n*1000, 2), 'ZAR', 'TPFRAUD03', 'app', 'transfer',
       cast(current_timestamp() - make_interval(0,0,0,0, cast(pmod(n,12) AS INT), cast(pmod(n*5,60) AS INT),0) AS TIMESTAMP),
       'Rapid app transfer','DEVFRAUD0001','102.65.10.4', false, 'ledger', current_timestamp()
FROM range(1,41) t(n);

-- ── C. ROUND-TRIP / CIRCULAR RING (4 accounts, closed loop) ──────────────
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
VALUES
  ('TXNRING01','ACCFRAUD01','ACCFRAUD01','ACCFRAUD02','debit', 1200000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 20 HOURS AS TIMESTAMP),'Ring leg 1','DEVFRAUD0001','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNRING02','ACCFRAUD02','ACCFRAUD02','ACCFRAUD03','debit', 1180000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 16 HOURS AS TIMESTAMP),'Ring leg 2','DEVFRAUD0002','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNRING03','ACCFRAUD03','ACCFRAUD03','ACCFRAUD04','debit', 1150000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 12 HOURS AS TIMESTAMP),'Ring leg 3','DEVFRAUD0003','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNRING04','ACCFRAUD04','ACCFRAUD04','ACCFRAUD01','debit', 1120000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 8 HOURS AS TIMESTAMP),'Ring leg 4 (closes loop)','DEVFRAUD0004','102.65.10.4', false,'ledger', current_timestamp());

-- ── D. DORMANT REACTIVATION (high value on 5 dormant accounts) ───────────
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
VALUES
  ('TXNDORM01','ACCDORM01','TPFRAUD01','ACCDORM01','credit', 1400000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 2 DAYS AS TIMESTAMP),'Dormant reactivation','DEVFRAUD0001','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNDORM02','ACCDORM02','TPFRAUD02','ACCDORM02','credit', 2100000.00,'ZAR','TPFRAUD02','eft','transfer', cast(current_timestamp() - INTERVAL 3 DAYS AS TIMESTAMP),'Dormant reactivation','DEVFRAUD0002','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNDORM03','ACCDORM03','TPFRAUD03','ACCDORM03','credit', 1750000.00,'ZAR','TPFRAUD03','eft','transfer', cast(current_timestamp() - INTERVAL 1 DAYS AS TIMESTAMP),'Dormant reactivation','DEVFRAUD0003','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNDORM04','ACCDORM04','TPFRAUD01','ACCDORM04','credit', 900000.00,'ZAR','TPFRAUD01','eft','transfer', cast(current_timestamp() - INTERVAL 4 DAYS AS TIMESTAMP),'Dormant reactivation','DEVFRAUD0004','102.65.10.4', false,'ledger', current_timestamp()),
  ('TXNDORM05','ACCDORM05','TPFRAUD02','ACCDORM05','credit', 2900000.00,'ZAR','TPFRAUD02','eft','transfer', cast(current_timestamp() - INTERVAL 5 DAYS AS TIMESTAMP),'Dormant reactivation','DEVFRAUD0005','102.65.10.4', false,'ledger', current_timestamp());

-- ── E. RISK-RATING JUMP (band 1 -> band 4) ───────────────────────────────
INSERT INTO nedbank_fraud_aml_bronze.risk_ratings VALUES
  ('RRFRAUD01A','CUSTFRAUD01','customer',1, TIMESTAMP'2026-03-01 09:00:00','kyc_engine','baseline', current_timestamp()),
  ('RRFRAUD01B','CUSTFRAUD01','customer',4, cast(current_timestamp() - INTERVAL 2 DAYS AS TIMESTAMP),'kyc_engine','adverse media + SAR trigger', current_timestamp()),
  ('RRFRAUD02A','CUSTFRAUD02','customer',2, TIMESTAMP'2026-03-01 09:00:00','kyc_engine','baseline', current_timestamp()),
  ('RRFRAUD02B','CUSTFRAUD02','customer',5, cast(current_timestamp() - INTERVAL 1 DAYS AS TIMESTAMP),'kyc_engine','PEP escalation', current_timestamp());

-- ── F. ADVERSE MEDIA HIT — matched at detection time against
--       bronze.adverse_media named_entities. No extra rows needed here.

-- ── G. BENEFICIAL-OWNERSHIP CHANGE (UBO flips) ───────────────────────────
INSERT INTO nedbank_fraud_aml_bronze.beneficial_ownership VALUES
  ('UBOFRAUD01A','TPFRAUD01','TPFRAUD02', 60.0, TIMESTAMP'2024-01-01 09:00:00','register', current_timestamp()),
  ('UBOFRAUD01B','TPFRAUD01','TPFRAUD03', 75.0, cast(current_timestamp() - INTERVAL 3 DAYS AS TIMESTAMP),'kyc_doc', current_timestamp());

-- ── H. ACCOUNT TAKEOVER (new device/geo + high-value debit < 1h) ─────────
INSERT INTO nedbank_fraud_aml_bronze.auth_events VALUES
  ('AEFRAUD01','ACCATO01', cast(current_timestamp() - INTERVAL 90 MINUTES AS TIMESTAMP), true, true, true,'DEV99999999','102.65.10.4','Lagos', current_timestamp());
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
VALUES
  ('TXNATO01','ACCATO01','ACCATO01','ACCFRAUD05','debit', 3500000.00,'ZAR','TPFRAUD02','app','transfer', cast(current_timestamp() - INTERVAL 45 MINUTES AS TIMESTAMP),'Post-takeover drain','DEV99999999','102.65.10.4', false,'ledger', current_timestamp());

-- ── I. IMPOSSIBLE TRAVEL (3 cards: JHB tap then London tap ~30 min later) ─
-- JHB (-26.2041, 28.0473) -> London (51.5074, -0.1278): ~9000 km in 0.5h.
INSERT INTO nedbank_fraud_aml_bronze.card_transactions
  (card_txn_id, card_id, account_id, amount, currency, merchant, merchant_category, channel, lat, lon, city, country, txn_ts, _ingested_at)
VALUES
  ('CTXFRAUD01A','CARDFRAUD01','ACCFRAUDC1', 2500.00,'ZAR','Sandton City','retail','chip', -26.1076, 28.0567,'Johannesburg','South Africa', cast(current_timestamp() - INTERVAL 5 HOURS AS TIMESTAMP), current_timestamp()),
  ('CTXFRAUD01B','CARDFRAUD01','ACCFRAUDC1', 8900.00,'GBP','Harrods London','retail','applepay', 51.4994, -0.1632,'London','United Kingdom', cast(current_timestamp() - INTERVAL 5 HOURS + INTERVAL 30 MINUTES AS TIMESTAMP), current_timestamp()),
  ('CTXFRAUD02A','CARDFRAUD02','ACCFRAUDC2', 1800.00,'ZAR','V&A Waterfront','retail','contactless', -33.9036, 18.4207,'Cape Town','South Africa', cast(current_timestamp() - INTERVAL 8 HOURS AS TIMESTAMP), current_timestamp()),
  ('CTXFRAUD02B','CARDFRAUD02','ACCFRAUDC2', 5400.00,'AED','Dubai Mall','retail','applepay', 25.1972, 55.2796,'Dubai','UAE', cast(current_timestamp() - INTERVAL 8 HOURS + INTERVAL 40 MINUTES AS TIMESTAMP), current_timestamp()),
  ('CTXFRAUD03A','CARDFRAUD03','ACCFRAUDC3', 3200.00,'ZAR','Gateway Durban','retail','chip', -29.7264, 31.0662,'Durban','South Africa', cast(current_timestamp() - INTERVAL 10 HOURS AS TIMESTAMP), current_timestamp()),
  ('CTXFRAUD03B','CARDFRAUD03','ACCFRAUDC3', 7600.00,'USD','JFK Terminal 4','retail','applepay', 40.6413, -73.7781,'New York','United States', cast(current_timestamp() - INTERVAL 10 HOURS + INTERVAL 25 MINUTES AS TIMESTAMP), current_timestamp());

-- ═══════════════════════════════════════════════════════════════════════════
-- WOW-A — THE HIDDEN MULE NETWORK (structuring + rapid movement + ER cluster)
-- ═══════════════════════════════════════════════════════════════════════════
-- One recruiter/aggregator (CUSTMULE00) + 7 mules (CUSTMULE01..07). All 7 mules
-- were onboarded within a 3-week window, and SHARE a device fingerprint, IP, and
-- physical address (opened by the same recruiter). Each mule receives 2–3
-- sub-threshold cash deposits (~R13–15k, just under the R25k CTR), then forwards
-- ~90% within 48h to the aggregator, which remits cross-border SWIFT to Onyx
-- Capital (Mauritius). 3 mule accounts were previously alerted and closed as
-- false positives in isolation (see alert_feedback seed in 03/governance).
INSERT INTO nedbank_fraud_aml_bronze.customers
  (customer_id, full_name, dob, national_id, tax_number, email, phone, address, city, country,
   segment, kyc_tier, declared_occupation, declared_monthly_turnover, pep_flag, employer_name,
   device_id, onboarded_at, onboarding_channel, source_system, _ingested_at)
VALUES
  -- Aggregator / recruiter
  ('CUSTMULE00','Kabelo Motaung', DATE'1987-04-18','ID7100000010','TAX710000010','kmotaung@demo.nedbank.co.za','+27829000010','88 Recruiter St','Soweto','South Africa','business','tier2','Self-employed', 30000.0, false,'Self','DEVMULE00A1', cast(date_sub(current_date(),40) AS TIMESTAMP),'branch','crm', current_timestamp()),
  -- 7 mules: shared address + shared device + shared IP, onboarded within 3 weeks
  ('CUSTMULE01','Lerato Sithole', DATE'2000-02-01','ID7100000011','TAX710000011','mule1@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Student', 5000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),35) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE02','Andile Mbeki', DATE'1999-07-14','ID7100000012','TAX710000012','mule2@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Student', 5000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),33) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE03','Zinhle Nkosi', DATE'2001-11-30','ID7100000013','TAX710000013','mule3@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Unemployed', 4000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),31) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE04','Tebogo Radebe', DATE'1998-05-09','ID7100000014','TAX710000014','mule4@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Student', 5000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),29) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE05','Ayanda Dube', DATE'2000-09-21','ID7100000015','TAX710000015','mule5@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Unemployed', 4000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),27) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE06','Sibusiso Ngcobo', DATE'1997-12-03','ID7100000016','TAX710000016','mule6@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Student', 5000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),25) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTMULE07','Palesa Mahlangu', DATE'1999-03-27','ID7100000017','TAX710000017','mule7@demo.nedbank.co.za','+27829000011','88 Recruiter St','Soweto','South Africa','pay_as_you_use','tier1','Student', 5000.0, false,'Self','DEVMULE0001', cast(date_sub(current_date(),24) AS TIMESTAMP),'app','crm', current_timestamp());

INSERT INTO nedbank_fraud_aml_bronze.accounts VALUES
  ('ACCMULE00','CUSTMULE00','migoals_transact','ZAR', cast(date_sub(current_date(),40) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 5000.00,'crm', current_timestamp()),
  ('ACCMULE01','CUSTMULE01','migoals_transact','ZAR', cast(date_sub(current_date(),35) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 1200.00,'crm', current_timestamp()),
  ('ACCMULE02','CUSTMULE02','migoals_transact','ZAR', cast(date_sub(current_date(),33) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 900.00,'crm', current_timestamp()),
  ('ACCMULE03','CUSTMULE03','migoals_transact','ZAR', cast(date_sub(current_date(),31) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 1500.00,'crm', current_timestamp()),
  ('ACCMULE04','CUSTMULE04','migoals_transact','ZAR', cast(date_sub(current_date(),29) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 800.00,'crm', current_timestamp()),
  ('ACCMULE05','CUSTMULE05','migoals_transact','ZAR', cast(date_sub(current_date(),27) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 1100.00,'crm', current_timestamp()),
  ('ACCMULE06','CUSTMULE06','migoals_transact','ZAR', cast(date_sub(current_date(),25) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 950.00,'crm', current_timestamp()),
  ('ACCMULE07','CUSTMULE07','migoals_transact','ZAR', cast(date_sub(current_date(),24) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 1300.00,'crm', current_timestamp());

-- Sub-threshold CASH DEPOSITS into each mule (3 per mule, ~R13–15k, under R25k CTR).
-- Placed within the last ~40h so they also fall in the structuring lookback window.
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
SELECT
  concat('TXNMULEDEP', lpad(m,1,'0'), lpad(k,1,'0'))                    AS transaction_id,
  concat('ACCMULE0', m)                                                 AS account_id,
  CAST(NULL AS STRING)                                                  AS from_acct,
  concat('ACCMULE0', m)                                                 AS to_acct,
  'credit'                                                              AS direction,
  round(19000 + m*100 + k*1500, 2)                                      AS amount,   -- ~R20.5k–24.5k, just under the R25k CTR
  'ZAR'                                                                 AS currency,
  CAST(NULL AS STRING)                                                  AS counterparty_id,
  element_at(array('cash_send','atm','branch'), cast(pmod(k,3)+1 AS INT)) AS channel,
  'cash'                                                                AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0,0, cast(6 + m*4 + k*3 AS INT),0,0) AS TIMESTAMP) AS txn_ts,
  'Cash deposit'                                                        AS description,
  'DEVMULE0001'                                                         AS device_id,
  '197.245.10.5'                                                        AS ip_address,
  false                                                                 AS is_cross_border,
  'ledger'                                                              AS source_system,
  current_timestamp()                                                   AS _ingested_at
FROM (SELECT explode(sequence(1,7)) AS m) mm
CROSS JOIN (SELECT explode(sequence(1,3)) AS k) kk;

-- Each mule FORWARDS ~90% to the aggregator within 48h (fires rapid movement on the
-- aggregator: total inflow ~R280k >= rapid_min_amount, then near-total cross-border out).
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
SELECT
  concat('TXNMULEFWD', lpad(m,1,'0'))                                   AS transaction_id,
  concat('ACCMULE0', m)                                                 AS account_id,
  concat('ACCMULE0', m)                                                 AS from_acct,
  'ACCMULE00'                                                           AS to_acct,
  'debit'                                                               AS direction,
  40000.00                                                              AS amount,   -- ~90% of the ~R44k deposited per mule
  'ZAR'                                                                 AS currency,
  'ACCMULE00'                                                           AS counterparty_id,
  'app'                                                                 AS channel,
  'transfer'                                                            AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0,0, cast(2 + m AS INT),0,0) AS TIMESTAMP) AS txn_ts,
  'Instant payment to K Motaung'                                        AS description,
  'DEVMULE0001'                                                         AS device_id,
  '197.245.10.5'                                                        AS ip_address,
  false                                                                 AS is_cross_border,
  'ledger'                                                              AS source_system,
  current_timestamp()                                                   AS _ingested_at
FROM (SELECT explode(sequence(1,7)) AS m) mm;

-- Aggregator receives the 7 mule forwards (credits) and remits cross-border SWIFT.
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
SELECT
  concat('TXNAGGIN', lpad(m,1,'0'))                                     AS transaction_id,
  'ACCMULE00'                                                           AS account_id,
  concat('ACCMULE0', m)                                                 AS from_acct,
  'ACCMULE00'                                                           AS to_acct,
  'credit'                                                              AS direction,
  40000.00                                                              AS amount,   -- matches each mule's forward (7 x R40k = R280k in, clears R250k rapid threshold)
  'ZAR'                                                                 AS currency,
  concat('ACCMULE0', m)                                                 AS counterparty_id,
  'app'                                                                 AS channel,
  'transfer'                                                            AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0,0, cast(2 + m AS INT),0,0) AS TIMESTAMP) AS txn_ts,
  'Aggregation credit'                                                  AS description,
  'DEVMULE00A1'                                                         AS device_id,
  '197.245.10.9'                                                        AS ip_address,
  false                                                                 AS is_cross_border,
  'ledger'                                                              AS source_system,
  current_timestamp()                                                   AS _ingested_at
FROM (SELECT explode(sequence(1,7)) AS m) mm;

INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
VALUES
  ('TXNAGGOUT1','ACCMULE00','ACCMULE00','TPFRAUD01','debit', 260000.00,'ZAR','TPFRAUD01','swift','transfer', cast(current_timestamp() - INTERVAL 1 HOURS AS TIMESTAMP),'Cross-border SWIFT to Onyx Capital (MU)','DEVMULE00A1','197.245.10.9', true,'ledger', current_timestamp());

-- ═══════════════════════════════════════════════════════════════════════════
-- WOW-C — THIRD-PARTY PAYMENT PROCESSOR LAYERING THROUGH GAMING MERCHANTS
-- ═══════════════════════════════════════════════════════════════════════════
-- Accounts that NEVER trip a legacy rule (amounts modest, no velocity spike, no
-- passthrough signature) but match the FATF typology: repeated card spend at
-- online-gaming/TPP merchants that then round-trips back as "winnings". The
-- retrospective typology sweep (advanced_aml + vector search) surfaces these.
INSERT INTO nedbank_fraud_aml_bronze.customers
  (customer_id, full_name, dob, national_id, tax_number, email, phone, address, city, country,
   segment, kyc_tier, declared_occupation, declared_monthly_turnover, pep_flag, employer_name,
   device_id, onboarded_at, onboarding_channel, source_system, _ingested_at)
VALUES
  ('CUSTGAME01','Werner Pretorius', DATE'1986-06-15','ID7200000021','TAX720000021','wpretorius@demo.nedbank.co.za','+27829100021','12 Retief St','Pretoria','South Africa','migoals_premium','tier2','Self-employed', 35000.0, false,'Self','DEVGAME0001', cast(date_sub(current_date(),400) AS TIMESTAMP),'app','crm', current_timestamp()),
  ('CUSTGAME02','Fatima Ismail', DATE'1991-10-08','ID7200000022','TAX720000022','fismail@demo.nedbank.co.za','+27829100022','7 Marine Dr','Durban','South Africa','migoals_plus','tier2','Small trader', 28000.0, false,'Self','DEVGAME0002', cast(date_sub(current_date(),380) AS TIMESTAMP),'app','crm', current_timestamp());

INSERT INTO nedbank_fraud_aml_bronze.accounts VALUES
  ('ACCGAME01','CUSTGAME01','migoals_transact','ZAR', cast(date_sub(current_date(),400) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 46000.00,'crm', current_timestamp()),
  ('ACCGAME02','CUSTGAME02','migoals_transact','ZAR', cast(date_sub(current_date(),380) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 38000.00,'crm', current_timestamp());

-- Layering pattern: modest, high-frequency debits to a TPP/gaming merchant, then
-- near-equal "winnings" credits back from the same processor. Below every legacy
-- threshold — only the typology sweep catches it.
INSERT INTO nedbank_fraud_aml_bronze.transactions
  (transaction_id, account_id, from_acct, to_acct, direction, amount, currency, counterparty_id,
   channel, merchant_category, txn_ts, description, device_id, ip_address, is_cross_border, source_system, _ingested_at)
SELECT
  concat('TXNGAME', lpad(a,1,'0'), 'D', lpad(n,2,'0'))                  AS transaction_id,
  concat('ACCGAME0', a)                                                 AS account_id,
  concat('ACCGAME0', a)                                                 AS from_acct,
  'TPP_LUCKYSTAKE'                                                      AS to_acct,
  'debit'                                                               AS direction,
  round(1500 + n*50, 2)                                                 AS amount,
  'ZAR'                                                                 AS currency,
  'TPP_LUCKYSTAKE'                                                      AS counterparty_id,
  'card'                                                                AS channel,
  'gaming'                                                              AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0, cast(pmod(n*3, 120) AS INT), cast(pmod(n,24) AS INT),0,0) AS TIMESTAMP) AS txn_ts,
  'LuckyStake Online (TPP)'                                            AS description,
  concat('DEVGAME000', a)                                               AS device_id,
  '160.119.20.7'                                                        AS ip_address,
  false                                                                 AS is_cross_border,
  'ledger'                                                              AS source_system,
  current_timestamp()                                                   AS _ingested_at
FROM (SELECT explode(sequence(1,2)) AS a) aa
CROSS JOIN (SELECT explode(sequence(1,30)) AS n) nn
UNION ALL
SELECT
  concat('TXNGAME', lpad(a,1,'0'), 'C', lpad(n,2,'0'))                  AS transaction_id,
  concat('ACCGAME0', a)                                                 AS account_id,
  'TPP_LUCKYSTAKE'                                                      AS from_acct,
  concat('ACCGAME0', a)                                                 AS to_acct,
  'credit'                                                              AS direction,
  round((1500 + n*50) * 0.95, 2)                                        AS amount,   -- "winnings" ~95% back
  'ZAR'                                                                 AS currency,
  'TPP_LUCKYSTAKE'                                                      AS counterparty_id,
  'eft'                                                                 AS channel,
  'gaming'                                                              AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0, cast(pmod(n*3, 120) AS INT), cast(pmod(n,24)+2 AS INT),0,0) AS TIMESTAMP) AS txn_ts,
  'LuckyStake payout (TPP)'                                            AS description,
  concat('DEVGAME000', a)                                               AS device_id,
  '160.119.20.7'                                                        AS ip_address,
  false                                                                 AS is_cross_border,
  'ledger'                                                              AS source_system,
  current_timestamp()                                                   AS _ingested_at
FROM (SELECT explode(sequence(1,2)) AS a) aa
CROSS JOIN (SELECT explode(sequence(1,30)) AS n) nn;

-- ═══════════════════════════════════════════════════════════════════════════
-- ITEM 4 — MESSY ENTITY-RESOLUTION DUPLICATES (graph "wow")
-- ═══════════════════════════════════════════════════════════════════════════
-- The same real person appears under three name spellings across three accounts,
-- sharing a national_id (deterministic ER collapse), plus a shared mobile and
-- device across two of them. Employer spelled three ways is ER noise the fuzzy
-- layer must tolerate.
INSERT INTO nedbank_fraud_aml_bronze.customers
  (customer_id, full_name, dob, national_id, tax_number, email, phone, address, city, country,
   segment, kyc_tier, declared_occupation, declared_monthly_turnover, pep_flag, employer_name,
   device_id, onboarded_at, onboarding_channel, source_system, _ingested_at)
VALUES
  ('CUSTDUP01','Jan van der Merwe', DATE'1979-02-14','ID7300000031','TAX730000031','jvdm@demo.nedbank.co.za','+27829200031','5 Loop St','Cape Town','South Africa','migoals_plus','tier2','Self-employed', 30000.0, false,'Blue Crane Logistics','DEVDUP0001', cast(date_sub(current_date(),700) AS TIMESTAMP),'branch','crm', current_timestamp()),
  ('CUSTDUP02','J. v.d. Merwe',      DATE'1979-02-14','ID7300000031','TAX730000031','janvdm2@demo.nedbank.co.za','+27829200031','5 Loop Street','Cape Town','South Africa','migoals_plus','tier1','Self employed', 30000.0, false,'Blue Crane Logistix','DEVDUP0001', cast(date_sub(current_date(),500) AS TIMESTAMP),'app','tabular', current_timestamp()),
  ('CUSTDUP03','Johannes vdMerwe',   DATE'1979-02-14','ID7300000031','TAX730000031','jvandermerwe@demo.nedbank.co.za','+27829200099','5A Loop St','Cape Town','South Africa','migoals_premium','tier2','Self-employed', 30000.0, false,'Bluecrane Logistics','DEVDUP0009', cast(date_sub(current_date(),300) AS TIMESTAMP),'agent','data_vault', current_timestamp());

INSERT INTO nedbank_fraud_aml_bronze.accounts VALUES
  ('ACCDUP01','CUSTDUP01','migoals_transact','ZAR', cast(date_sub(current_date(),700) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 42000.00,'crm', current_timestamp()),
  ('ACCDUP02','CUSTDUP02','savings_pocket','ZAR', cast(date_sub(current_date(),500) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 18000.00,'crm', current_timestamp()),
  ('ACCDUP03','CUSTDUP03','migoals_transact','ZAR', cast(date_sub(current_date(),300) AS TIMESTAMP),'active', cast(date_sub(current_date(),1) AS TIMESTAMP), 26000.00,'crm', current_timestamp());

-- WOW-A "killer line": 3 sibling mule accounts were previously alerted and CLOSED AS
-- FALSE POSITIVES in isolation — the exact failure mode of siloed rules engines. These
-- feedback rows pre-date the current structuring alerts; the copilot surfaces them when
-- it expands the network. (alert_feedback is the app write-back table — safe to seed.)
-- Guard-create the table so this seed is order-independent of sql/03_gold.
CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.alert_feedback (
  feedback_id      STRING,
  alert_id         STRING,
  status           STRING,
  analyst_feedback STRING,
  analyst          STRING,
  created_at       TIMESTAMP
) USING DELTA;
INSERT INTO nedbank_fraud_aml_gold.alert_feedback
  (feedback_id, alert_id, status, analyst_feedback, analyst, created_at)
VALUES
  ('FB-MULE-01','ALRT-STRUCT-ACCMULE01','dismissed','Small cash deposits, student account — no further action.','Thandeka Nkosi', cast(current_timestamp() - INTERVAL 21 DAYS AS TIMESTAMP)),
  ('FB-MULE-03','ALRT-STRUCT-ACCMULE03','dismissed','Below threshold, insufficient grounds — closed.','Rushil Naidoo', cast(current_timestamp() - INTERVAL 18 DAYS AS TIMESTAMP)),
  ('FB-MULE-05','ALRT-STRUCT-ACCMULE05','dismissed','One-off cash-in, no linked activity seen at the time.','Thandeka Nkosi', cast(current_timestamp() - INTERVAL 14 DAYS AS TIMESTAMP));
