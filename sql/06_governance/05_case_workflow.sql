-- Nedbank Sentinel — case workflow controls (NEXT_STEPS #4).
--
-- Two bank-workflow controls enforced by the app backend:
--   1. Case state machine (server/casestate.py): valid lifecycle transitions only
--      (new→assigned→in_progress→escalated/closed), via POST /api/sherlock/case/transition.
--      Rejected moves are written to the audit_log (action='transition_rejected').
--   2. Four-eyes on SAR filing (POST /api/sherlock/sar/submit): a SAR must be
--      approved by a SECOND, DISTINCT person — the `approved_by` column below records
--      the approver; same-person or missing approval is blocked and audited
--      (action='sar_blocked').
--
-- This file only records the schema change (the approver column); the transition
-- logic is code-side and unit-tested (tests/test_casestate.py).

USE CATALOG elexon_app_for_settlement_acc_catalog;

ALTER TABLE nedbank_fraud_aml_gold.sherlock_sar_filings
  ADD COLUMNS (approved_by STRING COMMENT 'Four-eyes: second approver, distinct from filed_by');
