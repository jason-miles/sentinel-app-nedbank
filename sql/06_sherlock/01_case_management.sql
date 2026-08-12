-- SherlockAML — Case-management data layer.
-- Analysts, teams, cases (one per alert with SLA/assignment/status), case notes,
-- SAR filings. Built over the existing gold.fraud_alerts + customers so the
-- Executive Overview, Alert Investigation queues, and SAR flow are all real.
--
-- Schema: elexon_app_for_settlement_acc_catalog.nedbank_fraud_aml_gold

USE CATALOG elexon_app_for_settlement_acc_catalog;

-- ── Teams (the 4 SherlockAML teams) ──────────────────────────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_gold.sherlock_teams AS
SELECT * FROM VALUES
  ('TEAM_TM',  'AML Transaction Monitoring'),
  ('TEAM_SW',  'Sanctions & Watchlist Screening'),
  ('TEAM_FR',  'Fraud Investigations'),
  ('TEAM_EDD', 'Enhanced Due Diligence (EDD)')
AS t(team_id, team_name);

-- ── Analysts (the 6 personas from the "View As" switcher) ────────────────
CREATE OR REPLACE TABLE nedbank_fraud_aml_gold.sherlock_analysts AS
SELECT * FROM VALUES
  ('AN_SARAH',  'Thandeka Nkosi',    'TEAM_TM',  'AML Transaction Monitoring'),
  ('AN_MICHAEL','Rushil Naidoo',     'TEAM_TM',  'AML Transaction Monitoring'),
  ('AN_LISA',   'Lerato Mokoena',    'TEAM_SW',  'Sanctions & Watchlist Screening'),
  ('AN_MARIA',  'Anele Mbatha',      'TEAM_FR',  'Fraud Investigations'),
  ('AN_NICOLE', 'Carel van Wyk',     'TEAM_EDD', 'Enhanced Due Diligence (EDD)'),
  ('AN_ROBERT', 'Fatima Patel',      'TEAM_EDD', 'Enhanced Due Diligence (EDD)')
AS t(analyst_id, analyst_name, team_id, team_name);
