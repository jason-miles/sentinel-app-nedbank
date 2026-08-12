-- Nedbank Sentinel — GenAI validation: LLM eval + guardrail results (NEXT_STEPS #8).
--
-- Populated by the app backend (server/routes/sar_eval.py) each time a SAR is
-- evaluated: LLM-as-judge groundedness + completeness (via Mosaic AI ai_query) and a
-- deterministic PII/length guardrail. Surfaced in the Compliance → Model Governance
-- tab ("LLM Evaluation & Guardrails"). An auditable record of how the GenAI surface
-- is validated — the answer to "how do you validate the AI?".

USE CATALOG elexon_app_for_settlement_acc_catalog;

CREATE TABLE IF NOT EXISTS nedbank_fraud_aml_gold.llm_eval_results (
  eval_id        STRING,
  eval_ts        TIMESTAMP,
  surface        STRING,      -- sar_narrative
  case_id        STRING,
  groundedness   DOUBLE,      -- 0..1 LLM-judge: narrative supported by evidence
  completeness   DOUBLE,      -- 0..1 LLM-judge: 4 required SAR sections present
  guardrail_pass BOOLEAN,     -- deterministic: no raw PII leak + min length
  guardrail_note STRING,
  overall_pass   BOOLEAN,
  model          STRING
) USING DELTA
COMMENT 'LLM evaluation + guardrail results for GenAI surfaces (faithfulness/completeness/guardrails).';

-- App service principal needs SELECT + MODIFY:
-- GRANT SELECT, MODIFY ON TABLE nedbank_fraud_aml_gold.llm_eval_results
--   TO `982e92ba-63ff-4de6-95ff-2bea54a734bd`;
