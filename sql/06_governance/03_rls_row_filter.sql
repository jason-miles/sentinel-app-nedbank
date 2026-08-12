-- Nedbank Sentinel — bank-grade governance: row-level security (NEXT_STEPS #5).
--
-- A UC ROW FILTER on sherlock_cases enforcing team/BU entitlement: an analyst only
-- sees cases for their own team, a compliance-oversight group sees everything, and
-- the app service principal keeps full visibility (so the app is never broken).
--
-- Visibility precedence (row visible when ANY is true):
--   1. Nedbank app service principal (ec6d288f-…)   → full visibility (app keeps working)
--   2. member of `aml_compliance_oversight` group   → full visibility (stewards/CCO)
--   3. deploying owner (jason.miles@databricks.com) → full visibility (demo/admin)
--   4. member of `aml_team_<team_id>` group         → only that team's cases
--   else                                            → no rows
--
-- NOTE: the app SP MUST be listed — the app runs every query as this one SP, so
-- omitting it silently empties every case-backed page (exec views, queue): each
-- query returns 200 but 0 rows. The client id below is the deployed nedbank-fraud-aml
-- app's service principal; re-point it if the app is recreated (get it from
-- `databricks apps get nedbank-fraud-aml`).
--
-- IMPORTANT — single-service-principal caveat: the app runs all queries as ONE
-- service principal, so through the APP every logged-in analyst inherits the SP's
-- full visibility (the app already scopes the queue by analyst_id at the query
-- layer). True PER-ANALYST enforcement at the UC layer needs On-Behalf-Of (OBO)
-- auth so queries run as the logged-in user — deferred (see NEXT_STEPS §5). This
-- filter is fully enforced for DIRECT queriers (Genie, ad-hoc SQL, BI tools), which
-- is where BU segregation matters most.

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE OR REPLACE FUNCTION nedbank_fraud_aml_gold.rls_case_team(team_id STRING)
RETURN
  current_user() = 'ccd34fed-be3f-4bfb-a13b-7064c4fe9eca'      -- Nedbank app SP (keeps app working)
  OR is_account_group_member('aml_compliance_oversight')        -- oversight/CCO
  OR current_user() = 'jason.miles@databricks.com'              -- deploying owner
  OR is_account_group_member(concat('aml_team_', lower(team_id)));  -- per-team analyst

ALTER TABLE nedbank_fraud_aml_gold.sherlock_cases
  SET ROW FILTER nedbank_fraud_aml_gold.rls_case_team ON (team_id);

-- Per-team groups to create (account admin) for real analyst scoping:
--   aml_team_team_tm, aml_team_team_edd, aml_team_team_sw, aml_team_team_fr
-- To remove:  ALTER TABLE nedbank_fraud_aml_gold.sherlock_cases DROP ROW FILTER;
