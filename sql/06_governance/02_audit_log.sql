-- Nedbank Sentinel — bank-grade governance: defensible audit trail (NEXT_STEPS #5).
--
-- Every case read, note, decision, and SAR action is appended here by the app
-- backend (server/routes/sherlock.py -> audit()) stamped with the acting persona and
-- timestamp. Surfaced in the app Compliance page "Audit Trail" tab
-- (/api/aml/audit). Append-only by convention; in production, enforce with a
-- retention/immutability policy + UC lineage for a fully defensible trail.

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.audit_log (
  event_id      STRING,
  event_ts      TIMESTAMP,
  actor         STRING,      -- acting analyst persona (or 'system')
  actor_role    STRING,      -- team / role context
  action        STRING,      -- case_open | sar_generate | sar_submit | case_action | note_add
  case_id       STRING,
  detail        STRING,      -- free-form (e.g. action type, reason)
  source        STRING       -- app surface that generated the event
) USING DELTA
COMMENT 'Immutable audit trail: every case read, decision, note, and SAR action stamped with acting persona + timestamp.';

-- App service principal needs SELECT + MODIFY (append):
-- GRANT SELECT, MODIFY ON TABLE nedbank_fraud_aml_gold.audit_log
--   TO `982e92ba-63ff-4de6-95ff-2bea54a734bd`;
