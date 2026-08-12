"""LLM evaluation + guardrails for the SAR GenAI surface (NEXT_STEPS #8).

Regulators ask "how is the AI validated?". This runs, per SAR:
  * LLM-as-judge evals (Mosaic AI ai_query): groundedness (is the narrative supported
    by the auto-gathered evidence?) and completeness (are the 4 required SAR sections
    present?), each scored 0..1.
  * A deterministic guardrail: the narrative must not leak raw PII identifiers
    (national_id / tax_number patterns) and must meet a minimum length.
Results persist to gold.llm_eval_results for an auditable AI-validation record.

The guardrail is a pure function (check_guardrail) so it is unit-testable.
"""
import re
import uuid
from fastapi import APIRouter
from pydantic import BaseModel

from ..db import fetch_all, execute
from ..config import GOLD_SCHEMA
from .sar_agents import orchestrate, OrchestrateReq

router = APIRouter(prefix="/api/aml", tags=["sar-eval"])

LLM = "databricks-meta-llama-3-3-70b-instruct"

# SA ID numbers are 13 digits; tax numbers 10. Flag long bare digit runs as raw-PII.
_PII_RE = re.compile(r"\b\d{10,13}\b")


def check_guardrail(narrative: str) -> tuple:
    """Deterministic guardrail: (passed: bool, note: str). No raw PII, min length."""
    if not narrative or len(narrative.strip()) < 120:
        return False, "narrative too short (<120 chars)"
    leaks = _PII_RE.findall(narrative or "")
    if leaks:
        return False, f"possible raw PII identifier(s) leaked: {len(leaks)}"
    return True, "no raw PII; length ok"


def _judge(instruction: str) -> float:
    """Ask the judge model for a 0..1 score; parse leniently, clamp."""
    row = fetch_all("SELECT ai_query(:m, :p) AS s",
                    [{"name": "m", "value": LLM}, {"name": "p", "value": instruction}])
    txt = (row[0]["s"] if row else "") or ""
    m = re.search(r"(\d*\.?\d+)", txt)
    if not m:
        return 0.0
    try:
        v = float(m.group(1))
    except ValueError:
        return 0.0
    if v > 1:  # model answered on a 0..100 or 0..10 scale
        v = v / 100 if v > 10 else v / 10
    return round(min(1.0, max(0.0, v)), 3)


class EvalReq(BaseModel):
    case_id: str


@router.post("/llm-eval/run")
def run_eval(req: EvalReq):
    """Generate a SAR for the case, then evaluate it (judges + guardrail) and record."""
    result = orchestrate(OrchestrateReq(case_id=req.case_id))
    if not result or "narrative" not in result:
        return {"detail": "not found"}
    narrative = result.get("narrative", "")
    # Reuse the brief orchestrate already built — avoids a second evidence gather
    # (extra vector-search + SQL reads).
    brief = result.get("evidence_brief", "")

    groundedness = _judge(
        "You are an AML SAR quality judge. On a 0..1 scale, how well is the SAR "
        "narrative SUPPORTED BY the case evidence (no unsupported claims)? Reply with "
        f"just the number.\n\nEvidence: {brief}\n\nNarrative: {narrative}")
    completeness = _judge(
        "You are an AML SAR quality judge. On a 0..1 scale, does this narrative cover "
        "all FOUR required sections — (1) summary of suspicious activity, (2) the "
        "pattern detected, (3) why it is suspicious, (4) recommended action? Reply "
        f"with just the number.\n\nNarrative: {narrative}")
    g_pass, g_note = check_guardrail(narrative)
    overall = bool(g_pass and groundedness >= 0.6 and completeness >= 0.6)

    eid = str(uuid.uuid4())
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.llm_eval_results
  (eval_id, eval_ts, surface, case_id, groundedness, completeness,
   guardrail_pass, guardrail_note, overall_pass, model)
VALUES (:id, current_timestamp(), 'sar_narrative', :cid, :g, :c, :gp, :gn, :op, :model)
""", [{"name": "id", "value": eid}, {"name": "cid", "value": req.case_id},
      {"name": "g", "value": str(groundedness)}, {"name": "c", "value": str(completeness)},
      {"name": "gp", "value": str(g_pass).lower()}, {"name": "gn", "value": g_note},
      {"name": "op", "value": str(overall).lower()}, {"name": "model", "value": LLM}])

    return {"eval_id": eid, "case_id": req.case_id, "groundedness": groundedness,
            "completeness": completeness, "guardrail_pass": g_pass,
            "guardrail_note": g_note, "overall_pass": overall}


@router.get("/llm-eval")
def eval_summary(limit: int = 25):
    """Recent eval runs + aggregate pass rates for the Model Governance surface."""
    rows = fetch_all(f"""
SELECT eval_ts, surface, case_id, groundedness, completeness,
       guardrail_pass, overall_pass
FROM {GOLD_SCHEMA}.llm_eval_results
ORDER BY eval_ts DESC LIMIT {int(limit)}
""")
    agg = fetch_all(f"""
SELECT count(*) AS runs,
       round(avg(groundedness),3) AS avg_groundedness,
       round(avg(completeness),3) AS avg_completeness,
       round(avg(CASE WHEN guardrail_pass THEN 1.0 ELSE 0.0 END),3) AS guardrail_pass_rate,
       round(avg(CASE WHEN overall_pass THEN 1.0 ELSE 0.0 END),3) AS overall_pass_rate
FROM {GOLD_SCHEMA}.llm_eval_results
""")
    return {"summary": agg[0] if agg else {}, "runs": rows}
