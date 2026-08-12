-- Nedbank — Fraud & AML SAMPLE DATA · Synthetic seeder (2/4): bulk ledger + card
-- transactions.  *** NEDBANK DEMO DATA — 100% SYNTHETIC ***
-- Target ~2-3M ledger transactions over the trailing 12 months (PRD §10).
-- Nedbank context: retail channels skew to the Nedbank banking app, card, ATM cash
-- and Cash Send; descriptions reflect everyday SA retail spend and salary/SASSA credits.

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── LEDGER TRANSACTIONS ──────────────────────────────────────────────────
-- ~200 txns per account on average across active accounts -> ~2.4M rows.
INSERT OVERWRITE nedbank_fraud_aml_bronze.transactions
WITH acct AS (
  SELECT account_id, customer_id,
         cast(regexp_replace(account_id, '^ACC0*', '') AS BIGINT) AS acct_num
  FROM nedbank_fraud_aml_bronze.accounts
  WHERE status = 'active'
),
txn AS (
  SELECT a.account_id, a.acct_num, e.n AS txn_seq
  FROM acct a
  LATERAL VIEW explode(sequence(1, cast(30 + pmod(a.acct_num, 30) AS INT))) e AS n
)
SELECT
  concat('TXN', lpad(cast(acct_num * 1000 + txn_seq AS BIGINT), 12, '0')) AS transaction_id,
  account_id,
  CASE WHEN pmod(txn_seq,2)=0 THEN account_id
       ELSE concat('ACC', lpad(cast(pmod(acct_num * 31 + txn_seq, 125000) + 1 AS BIGINT), 8, '0')) END AS from_acct,
  CASE WHEN pmod(txn_seq,2)=0
       THEN concat('ACC', lpad(cast(pmod(acct_num * 17 + txn_seq, 125000) + 1 AS BIGINT), 8, '0'))
       ELSE account_id END AS to_acct,
  CASE WHEN pmod(txn_seq,2)=0 THEN 'debit' ELSE 'credit' END AS direction,
  -- Retail-sized amounts: mostly small everyday value (R100–R25k)
  round(pmod(acct_num * 7 + txn_seq * 13, 25000) + 100, 2) AS amount,
  'ZAR' AS currency,
  concat('TP', lpad(cast(pmod(acct_num * 19 + txn_seq, 3000) + 1 AS INT), 6, '0')) AS counterparty_id,
  element_at(array('app','card','atm','cash_send','eft','branch'), cast(pmod(txn_seq, 6) + 1 AS INT)) AS channel,
  -- Everyday retail merchant categories (Benford-plausible mix); gaming is rare in the noise
  element_at(array('grocery','fuel','airtime','retail','utilities','restaurant','transport','grocery'),
             cast(pmod(txn_seq, 8) + 1 AS INT))                    AS merchant_category,
  cast(current_timestamp() - make_interval(0,0,0, cast(pmod(acct_num * 3 + txn_seq * 7, 365) AS INT), cast(pmod(txn_seq*11,24) AS INT), cast(pmod(txn_seq*7,60) AS INT),0) AS TIMESTAMP) AS txn_ts,
  element_at(array('Card purchase','Salary credit','SASSA grant','Nedbank Cash Send','Nedbank transfer','Prepaid airtime & data','DebiCheck debit order','ATM cash withdrawal','Immediate payment (RTC)'), cast(pmod(txn_seq,9)+1 AS INT)) AS description,
  concat('NBMONEY-', lpad(cast(pmod(acct_num * 40009, 90000000) AS BIGINT), 8, '0')) AS device_id,  -- client's own Nedbank Money app device
  concat('105.', cast(pmod(acct_num,255) AS INT), '.', cast(pmod(txn_seq*7,255) AS INT), '.', cast(pmod(acct_num*txn_seq,255) AS INT)) AS ip_address,
  false                                                            AS is_cross_border,
  'core_banking' AS source_system,
  current_timestamp() AS _ingested_at
FROM txn;

-- ── CARD / TAP TRANSACTIONS (geo, for impossible-travel) ─────────────────
-- Card-type accounts get ~80 tap transactions each within SA metro coords.
INSERT OVERWRITE nedbank_fraud_aml_bronze.card_transactions
WITH cards AS (
  SELECT account_id, customer_id,
         cast(regexp_replace(account_id, '^ACC0*', '') AS BIGINT) AS acct_num
  FROM nedbank_fraud_aml_bronze.accounts
  WHERE account_type = 'card' AND status = 'active'
),
taps AS (
  SELECT c.account_id, c.acct_num, e.n AS tap_seq
  FROM cards c
  LATERAL VIEW explode(sequence(1, cast(20 + pmod(c.acct_num, 20) AS INT))) e AS n
),
geo AS (
  SELECT *, pmod(acct_num + tap_seq, 5) AS gidx FROM taps
)
SELECT
  concat('CTX', lpad(cast(acct_num * 1000 + tap_seq AS BIGINT), 12, '0')) AS card_txn_id,
  concat('CARD', lpad(acct_num, 8, '0')) AS card_id,
  account_id,
  round(pmod(acct_num * 3 + tap_seq * 7, 6000) + 20, 2) AS amount,
  'ZAR' AS currency,
  element_at(array('Shoprite','Pick n Pay','Checkers','KFC','Engen','Takealot','Mr Price','Pep'), cast(pmod(tap_seq,8)+1 AS INT)) AS merchant,
  element_at(array('grocery','grocery','grocery','restaurant','fuel','retail','retail','retail'), cast(pmod(tap_seq,8)+1 AS INT)) AS merchant_category,
  element_at(array('chip','contactless','applepay','online'), cast(pmod(tap_seq,4)+1 AS INT)) AS channel,
  -- five SA metros; a card mostly stays in one metro
  element_at(array(-26.2041,-33.9249,-29.8587,-25.7479,-33.9321), cast(gidx+1 AS INT)) + (pmod(tap_seq,100)/1000.0) AS lat,
  element_at(array( 28.0473, 18.4241, 31.0218, 28.2293, 18.8602), cast(gidx+1 AS INT)) + (pmod(tap_seq,100)/1000.0) AS lon,
  element_at(array('Johannesburg','Cape Town','Durban','Pretoria','Paarl'), cast(gidx+1 AS INT)) AS city,
  'South Africa' AS country,
  cast(current_timestamp() - make_interval(0,0,0, cast(pmod(acct_num + tap_seq*3, 180) AS INT), cast(pmod(tap_seq*5,24) AS INT), cast(pmod(tap_seq*13,60) AS INT),0) AS TIMESTAMP) AS txn_ts,
  current_timestamp() AS _ingested_at
FROM geo;
