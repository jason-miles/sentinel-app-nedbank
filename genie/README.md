# Genie space — "Fraud & AML Analyst"

Curation for the Ask Sentinel Genie space (`<nedbank-genie-space-id>`,
warehouse `d0305022e6c3db8e`), backing the app's Ask Sentinel NL surface.

## What's curated (NEXT_STEPS #8)
- **Description = instructions**: a glossary (SAR / EDD / pKYC / PEP / UBO / typology),
  grain & join guidance (fraud_alerts / sherlock_cases → entity → customer_360), and
  answer conventions (severity domain, "high risk" mapping, sanctions confidence,
  anomaly_score ranking). Genie uses the space description as author context.
- **Sample questions**: 6 questions that map to the certified queries below.
- Verified: asking "How many customers require EDD review by risk band?" produced
  correct SQL over `pkyc_customer_risk` (understood "EDD" from the glossary).

## Certified example SQL
`fraud_aml_analyst_space.json` holds the intended v2 serialized space including
`curated_questions` with validated SQL (all 6 run against the live marts). NOTE: the
`create_or_update` REST path rejected the `instructions` / `curated_questions` keys
("Unknown field 'instructions'") — that serialized schema differs from the SDK's. The
glossary/instructions were therefore applied via the **description** field (which is
accepted and used), and the questions via **sample_questions**. To attach the SQL as
first-class certified answers, add them in the Genie UI (Space → Instructions → SQL
example queries) using the SQL in this file, or via the correct serialized schema once
confirmed.

## Re-apply
Use `manage_genie create_or_update` with `space_id`, `display_name`, the description,
and `sample_questions` (see the git history for the exact call), or edit in the UI.
