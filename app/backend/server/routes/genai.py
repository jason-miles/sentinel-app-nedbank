"""GenAI capabilities for Nedbank Sentinel:
- Genie 'Ask Sentinel' (NL -> governed SQL) via the Genie Conversation API
- Executive AI briefing (ai_query over KPIs)
- Per-case AI risk triage (rescore + recommended action)
- Per-alert smart-prioritization blurb
"""
import os
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from ..db import fetch_all, ai_query, parallel
from ..http import fetch_one_or_404
from ..config import get_workspace_client, GOLD_SCHEMA

router = APIRouter(prefix="/api/genai", tags=["genai"])

GENIE_SPACE = os.environ.get("SENTINEL_GENIE_SPACE", "01f1962af9e61338a2c438fe01a7f352")



# ─────────────────────── Genie "Ask Sentinel" ────────────────────────────
class Ask(BaseModel):
    question: str
    conversation_id: Optional[str] = None


@router.post("/ask")
def ask(a: Ask):
    """Ask the Fraud & AML Analyst Genie space a natural-language question.
    Returns the narrative answer, the generated SQL, and result rows."""
    w = get_workspace_client()
    try:
        if a.conversation_id:
            msg = w.genie.create_message_and_wait(GENIE_SPACE, a.conversation_id, a.question)
        else:
            msg = w.genie.start_conversation_and_wait(GENIE_SPACE, a.question)
    except Exception as e:  # noqa: BLE001
        return {"ok": False, "error": f"Genie unavailable: {type(e).__name__}"}

    answer_text, sql, rows, cols = "", "", [], []
    for att in (msg.attachments or []):
        if getattr(att, "text", None) and att.text.content:
            answer_text += att.text.content + "\n"
        if getattr(att, "query", None):
            sql = att.query.query or ""
            try:
                res = w.genie.get_message_query_result_by_attachment(
                    GENIE_SPACE, msg.conversation_id, msg.id, att.attachment_id
                )
                sd = res.statement_response
                if sd and sd.result and sd.manifest:
                    cols = [c.name for c in sd.manifest.schema.columns]
                    rows = [dict(zip(cols, r)) for r in (sd.result.data_array or [])][:100]
            except Exception:  # noqa: BLE001
                pass
    return {
        "ok": True,
        "answer": answer_text.strip() or "Genie returned a result set.",
        "sql": sql,
        "columns": cols,
        "rows": rows,
        "conversation_id": msg.conversation_id,
    }


# ─────────────────────── Executive AI briefing ───────────────────────────
@router.get("/exec-briefing")
def exec_briefing():
    # Three independent MV reads before the LLM call — fan out concurrently.
    k, scen, teams = parallel(
        lambda: fetch_all(f"SELECT * FROM {GOLD_SCHEMA}.sherlock_exec_kpis"),
        lambda: fetch_all(f"SELECT scenario, alerts FROM {GOLD_SCHEMA}.sherlock_by_scenario ORDER BY alerts DESC LIMIT 3"),
        lambda: fetch_all(f"SELECT team_name, past_due, avg_hours FROM {GOLD_SCHEMA}.sherlock_team_performance ORDER BY past_due DESC LIMIT 2"),
    )
    kpi = k[0] if k else {}
    top_scen = ", ".join(f"{r['scenario']} ({r['alerts']})" for r in scen)
    worst_team = ", ".join(f"{r['team_name']} ({r['past_due']} past due, {r['avg_hours']}h avg)" for r in teams)
    prompt = (
        "You are a Chief Compliance Officer's AI analyst for Nedbank Limited, a South "
        "African retail bank regulated under the FIC Act (FICA) and supervised by the SARB "
        "Prudential Authority and the Financial Intelligence Centre (FIC). Use South African "
        "framing (STRs/CTRs to the FIC via goAML; POPIA for data). Write a concise 4-5 sentence "
        "executive briefing on the AML program's current state. Data: "
        f"case volume {kpi.get('case_volume')}, avg investigation hours {kpi.get('avg_investigation_hours')}, "
        f"false positive rate {kpi.get('false_positive_rate')}%, past-due alerts {kpi.get('past_due_alerts')}, "
        f"upcoming deadlines {kpi.get('upcoming_deadlines')}, transaction amount {kpi.get('transaction_amount_m')}m. "
        f"Top scenarios: {top_scen}. Teams under pressure: {worst_team}. "
        "Highlight what's improving, what needs attention, and one recommended action."
    )
    return {"briefing": ai_query(prompt), "kpis": kpi}


# ─────────────────────── Per-case AI risk triage ─────────────────────────
class Triage(BaseModel):
    case_id: str


@router.post("/triage")
def triage(t: Triage):
    c = fetch_one_or_404(f"""
SELECT customer_name, scenario, priority, status, risk_score, amount, days_open, team_name
FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid
""", [{"name": "cid", "value": t.case_id}])
    prompt = (
        "You are an AML triage AI. Given this case, output exactly three short labelled lines: "
        "'AI Risk: <0-100>', 'Recommendation: <escalate|file SAR|dismiss|enhanced monitoring>', "
        "'Rationale: <one sentence>'. "
        f"Case: customer {c['customer_name']}, scenario {c['scenario']}, rules risk {c['risk_score']}, "
        f"priority {c['priority']}, amount {c['amount']}, {c['days_open']} days open, team {c['team_name']}."
    )
    return {"case_id": t.case_id, "triage": ai_query(prompt), "rules_risk": c["risk_score"]}


# ─────────────────────── Smart prioritization blurb ──────────────────────
class Blurb(BaseModel):
    case_id: str


@router.post("/prioritize")
def prioritize(b: Blurb):
    c = fetch_one_or_404(f"""
SELECT customer_name, scenario, priority, risk_score, amount, days_open
FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid
""", [{"name": "cid", "value": b.case_id}])
    prompt = (
        "In ONE sentence, tell an AML analyst why this alert matters and the single best next step. "
        f"Scenario {c['scenario']}, risk {c['risk_score']}, priority {c['priority']}, "
        f"amount {c['amount']}, {c['days_open']} days open, customer {c['customer_name']}."
    )
    return {"case_id": b.case_id, "blurb": ai_query(prompt)}
