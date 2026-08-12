-- Nedbank Sentinel — app write-back tables (create-if-not-exists).
--
-- These tables are written by the app backend at runtime (case notes, case actions,
-- SAR filings) but were previously never CREATEd by SQL, so a fresh workspace 500s on
-- the investigation/case-detail page until the first write. This file creates them up
-- front (idempotent) and seeds a few notes/actions on the hero cases so the demo's
-- investigation timeline looks realistic from the first click.
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.sherlock_case_notes (
  note_id    STRING,
  case_id    STRING,
  author     STRING,
  note       STRING,
  note_type  STRING,   -- analyst | system
  created_at TIMESTAMP
) USING DELTA
COMMENT 'App write-back: analyst investigation notes per case.';

CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.sherlock_case_actions (
  action_id  STRING,
  case_id    STRING,
  action     STRING,   -- escalate | request_docs | close | reassign | ...
  reason     STRING,
  actor      STRING,
  created_at TIMESTAMP
) USING DELTA
COMMENT 'App write-back: case actions/decisions taken by analysts.';

CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.sherlock_sar_filings (
  sar_id        STRING,
  case_id       STRING,
  customer_name STRING,
  scenario      STRING,
  narrative     STRING,
  decision      STRING,
  filed_by      STRING,
  filed_at      TIMESTAMP,
  approved_by   STRING COMMENT 'Four-eyes: second approver, distinct from filed_by'
) USING DELTA
COMMENT 'App write-back: SAR/STR filings with four-eyes approver.';

-- Seed investigation notes on the hero cases so the timeline is populated on demo day.
-- Idempotent: clear any prior seeded hero rows first so re-runs don't accumulate dupes.
DELETE FROM nedbank_fraud_aml_gold.sherlock_case_notes WHERE note_id LIKE 'NOTE-9%';
DELETE FROM nedbank_fraud_aml_gold.sherlock_case_actions WHERE action_id LIKE 'ACT-9%';
INSERT INTO nedbank_fraud_aml_gold.sherlock_case_notes
  (note_id, case_id, author, note, note_type, created_at)
VALUES
  ('NOTE-9001A','CASE-90001','Thandeka Nkosi','Alert opened: three cash deposits just under R25k over ~40h on a recently-opened Nedbank account. Checking for linked accounts.','analyst', current_timestamp() - INTERVAL 3 HOURS),
  ('NOTE-9001B','CASE-90001','Thandeka Nkosi','Entity resolution links this account to six others sharing device DEVMULE0001 and address 88 Recruiter St. Escalating as suspected mule network.','analyst', current_timestamp() - INTERVAL 1 HOURS),
  ('NOTE-9002A','CASE-90002','Anele Mbatha','Aggregator receives ~R40k from each of seven mules then remits R260k cross-border SWIFT to Onyx Capital (Mauritius). Classic layering.','analyst', current_timestamp() - INTERVAL 90 MINUTES),
  ('NOTE-9003A','CASE-90003','Carel van Wyk','Flagged by retrospective FATF typology sweep (gaming/TPP layering), not a live rule. ~30 gaming debits with near-equal payouts; net ~0.','analyst', current_timestamp() - INTERVAL 2 DAYS);

INSERT INTO nedbank_fraud_aml_gold.sherlock_case_actions
  (action_id, case_id, action, reason, actor, created_at)
VALUES
  ('ACT-9001A','CASE-90001','escalate','Suspected 7-account mule network; sub-threshold structuring','Thandeka Nkosi', current_timestamp() - INTERVAL 55 MINUTES),
  ('ACT-9002A','CASE-90002','escalate','Cross-border layering via aggregation account','Anele Mbatha', current_timestamp() - INTERVAL 80 MINUTES),
  ('ACT-9003A','CASE-90003','request_docs','Source-of-funds for high-frequency gaming/TPP flows','Carel van Wyk', current_timestamp() - INTERVAL 1 DAYS);
