"""SherlockAML endpoints — personas, executive analytics, investigation queues,
case actions, multi-agent assistant, SAR generation, and graph explorer."""
import uuid
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from ..db import fetch_all, execute
from ..config import GOLD_SCHEMA, SILVER_SCHEMA
from ..casestate import can_transition, transition_error
from ..sla import sla_status

router = APIRouter(prefix="/api/sherlock", tags=["sherlock"])

LLM = "databricks-meta-llama-3-3-70b-instruct"


def audit(action: str, actor: str = "system", case_id: str = "", detail: str = "",
          actor_role: str = "", source: str = "app"):
    """Append an immutable audit event. Best-effort: auditing must never break the
    user action, so failures are swallowed (the write is a fire-and-forget INSERT)."""
    try:
        execute(f"""
INSERT INTO {GOLD_SCHEMA}.audit_log
  (event_id, event_ts, actor, actor_role, action, case_id, detail, source)
VALUES (:id, current_timestamp(), :actor, :role, :action, :cid, :detail, :src)
""", [{"name": "id", "value": str(uuid.uuid4())}, {"name": "actor", "value": actor},
      {"name": "role", "value": actor_role}, {"name": "action", "value": action},
      {"name": "cid", "value": case_id}, {"name": "detail", "value": detail},
      {"name": "src", "value": source}])
    except Exception:
        pass


# ─────────────────────────── Personas ────────────────────────────────────
@router.get("/personas")
def personas():
    return fetch_all(f"""
SELECT analyst_id, analyst_name, team_id, team_name
FROM {GOLD_SCHEMA}.sherlock_analysts ORDER BY analyst_name
""")


# ─────────────────────── Executive Overview ──────────────────────────────
@router.get("/exec/kpis")
def exec_kpis():
    rows = fetch_all(f"SELECT * FROM {GOLD_SCHEMA}.sherlock_exec_kpis")
    return rows[0] if rows else {}


@router.get("/exec/daily-new")
def exec_daily_new():
    return fetch_all(f"SELECT d, alerts FROM {GOLD_SCHEMA}.sherlock_daily_new ORDER BY d")


@router.get("/exec/outstanding")
def exec_outstanding():
    return fetch_all(f"SELECT due_date, alerts FROM {GOLD_SCHEMA}.sherlock_outstanding ORDER BY due_date")


@router.get("/exec/by-scenario")
def exec_by_scenario():
    return fetch_all(f"SELECT scenario, alerts FROM {GOLD_SCHEMA}.sherlock_by_scenario ORDER BY alerts DESC")


@router.get("/exec/priority-status")
def exec_priority_status():
    return fetch_all(f"SELECT priority, status, alerts FROM {GOLD_SCHEMA}.sherlock_priority_status")


@router.get("/exec/resolution-flow")
def exec_resolution_flow():
    return fetch_all(f"SELECT source, target, value FROM {GOLD_SCHEMA}.sherlock_resolution_flow")


@router.get("/exec/team-performance")
def exec_team_performance():
    return fetch_all(f"""
SELECT team_name, cases, closed, past_due, avg_hours, avg_risk
FROM {GOLD_SCHEMA}.sherlock_team_performance ORDER BY cases DESC
""")


# ─────────────────────── Alert Investigation ─────────────────────────────
_PRIORITIES = {"critical", "high", "medium", "low"}


@router.get("/queue/{analyst_id}")
def my_queue(analyst_id: str, priority: Optional[str] = None, scenario: Optional[str] = None):
    """Per-analyst queue KPIs + weekly scenario breakdown + active alerts.

    Optional server-side filters on the active-alerts list: `priority` (validated
    against the known set) and `scenario` (bound as a parameter — free text but never
    interpolated). KPIs/weekly stay unfiltered so the headline numbers are stable."""
    p = [{"name": "aid", "value": analyst_id}]
    kpis = fetch_all(f"""
SELECT
  sum(CASE WHEN priority='critical' THEN 1 ELSE 0 END) AS critical,
  sum(CASE WHEN priority='high' THEN 1 ELSE 0 END) AS high,
  count(*) AS total,
  sum(CASE WHEN status='new' THEN 1 ELSE 0 END) AS new_alerts
FROM {GOLD_SCHEMA}.sherlock_cases WHERE analyst_id = :aid
""", p)
    weekly = fetch_all(f"""
SELECT date_trunc('WEEK', opened_at) AS week, scenario, count(*) AS alerts
FROM {GOLD_SCHEMA}.sherlock_cases WHERE analyst_id = :aid
GROUP BY date_trunc('WEEK', opened_at), scenario ORDER BY week
""", p)
    filt = ""
    ap = list(p)
    if priority and priority.lower() in _PRIORITIES:
        filt += " AND c.priority = :prio"
        ap.append({"name": "prio", "value": priority.lower()})
    if scenario:
        filt += " AND c.scenario = :scen"
        ap.append({"name": "scen", "value": scenario})
    active = fetch_all(f"""
SELECT c.case_id, c.alert_num, c.customer_name, c.scenario, c.risk_score, c.priority,
       c.amount, c.days_open, c.status, s.ai_risk, s.model_version
FROM {GOLD_SCHEMA}.sherlock_cases c
LEFT JOIN {GOLD_SCHEMA}.ml_alert_scores s ON s.case_id = c.case_id
WHERE c.analyst_id = :aid AND c.status <> 'closed'{filt}
ORDER BY coalesce(s.ai_risk, c.risk_score) DESC,
         CASE c.priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END,
         c.days_open DESC
LIMIT 100
""", ap)
    # Enrich each active case with its SLA status (priority-driven target vs days_open).
    for a in active:
        a["sla"] = sla_status(a.get("priority"), a.get("days_open"))
    return {"kpis": kpis[0] if kpis else {}, "weekly": weekly, "active_alerts": active}


@router.get("/case/{case_id}")
def case_detail(case_id: str, actor: str = "Sarah Chen"):
    """Investigation page: case, flagged transactions, entity network, notes, actions."""
    audit("case_open", actor=actor, case_id=case_id, detail="Opened case investigation", source="investigation")
    p = [{"name": "cid", "value": case_id}]
    rows = fetch_all(f"""
SELECT c.case_id, c.alert_num, c.customer_id, c.customer_name, c.scenario, c.priority, c.status,
       c.team_name, c.analyst_name, c.risk_score, c.amount, c.days_open, c.due_date, c.investigation_hours,
       -- Served-model AI risk (replaces the old ai_query placeholder): the registered
       -- UC model's SAR probability blended with the rules score. Nullable if the case
       -- has not been batch-scored yet.
       s.ai_risk, s.model_score, s.rules_score, s.model_version
FROM {GOLD_SCHEMA}.sherlock_cases c
LEFT JOIN {GOLD_SCHEMA}.ml_alert_scores s ON s.case_id = c.case_id
WHERE c.case_id = :cid
""", p)
    if not rows:
        return {"detail": "not found"}
    case = rows[0]
    cust = case.get("customer_id")
    # flagged transactions for this customer's accounts
    txns = fetch_all(f"""
SELECT t.transaction_id, t.amount, t.direction, t.channel, t.txn_ts, t.description, t.counterparty_id
FROM {SILVER_SCHEMA}.transactions t
JOIN {SILVER_SCHEMA}.accounts a ON a.account_id = t.account_id
WHERE a.customer_id = :cust
ORDER BY t.amount DESC LIMIT 12
""", [{"name": "cust", "value": cust}]) if cust else []
    # counterparties (entity relationships)
    parties = fetch_all(f"""
SELECT DISTINCT t.counterparty_id, tp.full_name, tp.country
FROM {SILVER_SCHEMA}.transactions t
JOIN {SILVER_SCHEMA}.accounts a ON a.account_id = t.account_id
LEFT JOIN {SILVER_SCHEMA}.third_parties tp ON tp.third_party_id = t.counterparty_id
WHERE a.customer_id = :cust AND t.counterparty_id IS NOT NULL
LIMIT 15
""", [{"name": "cust", "value": cust}]) if cust else []
    notes = fetch_all(f"""
SELECT author, note, note_type, created_at FROM {GOLD_SCHEMA}.sherlock_case_notes
WHERE case_id = :cid ORDER BY created_at DESC LIMIT 20
""", p)
    actions = fetch_all(f"""
SELECT action, reason, actor, created_at FROM {GOLD_SCHEMA}.sherlock_case_actions
WHERE case_id = :cid ORDER BY created_at DESC LIMIT 20
""", p)
    case["flagged_transactions"] = txns
    case["counterparties"] = parties
    case["notes"] = notes
    case["actions"] = actions
    case["sla"] = sla_status(case.get("priority"), case.get("days_open"))
    return case


class Note(BaseModel):
    case_id: str
    note: str
    author: str = "Sarah Chen"


@router.post("/case/note")
def add_note(n: Note):
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.sherlock_case_notes (note_id, case_id, author, note, note_type, created_at)
VALUES (:id, :cid, :author, :note, 'analyst', current_timestamp())
""", [{"name": "id", "value": str(uuid.uuid4())}, {"name": "cid", "value": n.case_id},
      {"name": "author", "value": n.author}, {"name": "note", "value": n.note}])
    audit("note_add", actor=n.author, case_id=n.case_id, detail="Added investigation note", source="investigation")
    return {"ok": True}


class Action(BaseModel):
    case_id: str
    action: str            # escalate | dismiss | proceed_sar
    reason: str = ""
    actor: str = "Sarah Chen"


@router.post("/case/action")
def case_action(a: Action):
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.sherlock_case_actions (action_id, case_id, action, reason, actor, created_at)
VALUES (:id, :cid, :action, :reason, :actor, current_timestamp())
""", [{"name": "id", "value": str(uuid.uuid4())}, {"name": "cid", "value": a.case_id},
      {"name": "action", "value": a.action}, {"name": "reason", "value": a.reason},
      {"name": "actor", "value": a.actor}])
    audit("case_action", actor=a.actor, case_id=a.case_id,
          detail=f"{a.action}" + (f": {a.reason}" if a.reason else ""), source="investigation")
    return {"ok": True}


class Transition(BaseModel):
    case_id: str
    target: str            # assigned | in_progress | escalated | closed
    actor: str = "Sarah Chen"


@router.post("/case/transition")
def case_transition(t: Transition):
    """Move a case to a new lifecycle status — only if the transition is valid
    (state machine in server/casestate.py). Rejected moves are audited too."""
    rows = fetch_all(f"SELECT status FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid",
                     [{"name": "cid", "value": t.case_id}])
    if not rows:
        return {"ok": False, "error": "case not found"}
    current = rows[0]["status"]
    err = transition_error(current, t.target)
    if err:
        audit("transition_rejected", actor=t.actor, case_id=t.case_id,
              detail=f"{current} -> {t.target}: {err}", source="workflow")
        return {"ok": False, "error": err, "current": current}
    execute(f"UPDATE {GOLD_SCHEMA}.sherlock_cases SET status = :s WHERE case_id = :cid",
            [{"name": "s", "value": t.target}, {"name": "cid", "value": t.case_id}])
    audit("case_transition", actor=t.actor, case_id=t.case_id,
          detail=f"{current} -> {t.target}", source="workflow")
    return {"ok": True, "from": current, "to": t.target}


class Reassign(BaseModel):
    case_id: str
    to_analyst_id: str
    to_analyst_name: str
    to_team_id: str = ""
    to_team_name: str = ""
    actor: str = "Sarah Chen"


@router.post("/case/reassign")
def case_reassign(r: Reassign):
    """Reassign a case to another analyst/team (audited)."""
    rows = fetch_all(f"SELECT analyst_name FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid",
                     [{"name": "cid", "value": r.case_id}])
    if not rows:
        return {"ok": False, "error": "case not found"}
    prev = rows[0]["analyst_name"]
    sets = ["analyst_id = :aid", "analyst_name = :aname"]
    params = [{"name": "aid", "value": r.to_analyst_id}, {"name": "aname", "value": r.to_analyst_name},
              {"name": "cid", "value": r.case_id}]
    if r.to_team_id:
        sets += ["team_id = :tid", "team_name = :tname"]
        params += [{"name": "tid", "value": r.to_team_id}, {"name": "tname", "value": r.to_team_name}]
    execute(f"UPDATE {GOLD_SCHEMA}.sherlock_cases SET {', '.join(sets)} WHERE case_id = :cid", params)
    audit("case_reassign", actor=r.actor, case_id=r.case_id,
          detail=f"{prev} -> {r.to_analyst_name}" + (f" ({r.to_team_name})" if r.to_team_name else ""),
          source="workflow")
    return {"ok": True, "from": prev, "to": r.to_analyst_name}


# ─────────────────── Multi-agent assistant (ai_query) ────────────────────
AGENTS = {
    "supervisor": "You are the AML Multi-Agent Supervisor. Coordinate a concise, expert recommendation.",
    "policy": "You are the AML Policy Q&A agent. Answer with reference to AML/CFT policy and typologies.",
    "adverse_media": "You are the Adverse Media Screening agent. Summarise reputational/financial-crime risk.",
    "investigation": "You are the Case Investigation agent. Analyse transaction patterns and entity links.",
    "sar": "You are the SAR Drafting agent. Produce regulator-ready SAR narrative content.",
}


class AgentChat(BaseModel):
    agent: str = "supervisor"
    question: str
    case_id: Optional[str] = None


@router.post("/agent/chat")
def agent_chat(q: AgentChat):
    persona = AGENTS.get(q.agent, AGENTS["supervisor"])
    context = ""
    if q.case_id:
        rows = fetch_all(f"""
SELECT customer_name, scenario, priority, risk_score, amount, days_open
FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid
""", [{"name": "cid", "value": q.case_id}])
        if rows:
            c = rows[0]
            context = (f" Case context: customer {c['customer_name']}, scenario {c['scenario']}, "
                       f"priority {c['priority']}, risk score {c['risk_score']}, amount {c['amount']}, "
                       f"{c['days_open']} days open.")
    prompt = f"{persona}{context} Question: {q.question}. Answer in 3-4 sentences with a clear recommendation."
    # Bind the prompt as a parameter (never interpolate untrusted text into SQL).
    rows = fetch_all(
        "SELECT ai_query(:model, :prompt) AS answer",
        [{"name": "model", "value": LLM}, {"name": "prompt", "value": prompt}],
    )
    return {"agent": q.agent, "answer": rows[0]["answer"] if rows else ""}


# ─────────────────────────── SAR generation ──────────────────────────────
class SarGen(BaseModel):
    case_id: str


@router.post("/sar/generate")
def sar_generate(s: SarGen):
    rows = fetch_all(f"""
SELECT case_id, customer_name, scenario, priority, risk_score, amount, days_open, team_name
FROM {GOLD_SCHEMA}.sherlock_cases WHERE case_id = :cid
""", [{"name": "cid", "value": s.case_id}])
    if not rows:
        return {"detail": "not found"}
    c = rows[0]
    prompt = (
        "Draft a concise, regulator-ready Suspicious Activity Report (SAR) narrative "
        f"for the following AML case. Customer: {c['customer_name']}. Detection scenario: {c['scenario']}. "
        f"Risk score: {c['risk_score']}/100. Priority: {c['priority']}. Amount involved: {c['amount']}. "
        f"Days under investigation: {c['days_open']}. Investigating team: {c['team_name']}. "
        "Include: (1) summary of suspicious activity, (2) the pattern detected, "
        "(3) why it is suspicious, (4) recommended action. Keep it factual and professional."
    )
    out = fetch_all(
        "SELECT ai_query(:model, :prompt) AS narrative",
        [{"name": "model", "value": LLM}, {"name": "prompt", "value": prompt}],
    )
    return {
        "case_id": c["case_id"],
        "customer_name": c["customer_name"],
        "scenario": c["scenario"],
        "priority": c["priority"],
        "risk_score": c["risk_score"],
        "amount": c["amount"],
        "narrative": out[0]["narrative"] if out else "",
    }


class SarSubmit(BaseModel):
    case_id: str
    customer_name: str
    scenario: str
    narrative: str
    decision: str = "SAR Filed"
    filed_by: str = "Sarah Chen"
    approved_by: str = ""      # four-eyes: a SECOND person must approve the filing


@router.post("/sar/submit")
def sar_submit(s: SarSubmit):
    # Four-eyes control: a SAR filing must be approved by a second, distinct person.
    approver = (s.approved_by or "").strip()
    if not approver:
        return {"ok": False, "error": "four-eyes: a second approver is required to file a SAR"}
    if approver.casefold() == (s.filed_by or "").strip().casefold():
        audit("sar_blocked", actor=s.filed_by, case_id=s.case_id,
              detail="four-eyes violation: approver == filer", source="sar_filing")
        return {"ok": False, "error": "four-eyes: the approver must differ from the filer"}
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.sherlock_sar_filings
  (sar_id, case_id, customer_name, scenario, narrative, decision, filed_by, filed_at, approved_by)
VALUES (:id, :cid, :cust, :scen, :narr, :dec, :by, current_timestamp(), :appr)
""", [{"name": "id", "value": str(uuid.uuid4())}, {"name": "cid", "value": s.case_id},
      {"name": "cust", "value": s.customer_name}, {"name": "scen", "value": s.scenario},
      {"name": "narr", "value": s.narrative}, {"name": "dec", "value": s.decision},
      {"name": "by", "value": s.filed_by}, {"name": "appr", "value": approver}])
    audit("sar_submit", actor=s.filed_by, case_id=s.case_id,
          detail=f"{s.decision} — {s.scenario} (approved by {approver})", source="sar_filing")
    return {"ok": True, "sar_id": s.case_id, "approved_by": approver}


# ─────────────────────────── Graph Explorer ──────────────────────────────
@router.get("/graph")
def graph(q: Optional[str] = None, limit: int = 12):
    """Knowledge graph: top-risk customers + their accounts + counterparties +
    watchlist hits. Optional NL query filters the seed customers via ai_query
    keyword extraction (kept simple: match against name/scenario/country)."""
    seed = fetch_all(f"""
SELECT customer_id, full_name, city, country, risk FROM (
  SELECT c.customer_id, cust.full_name, cust.city, cust.country,
         coalesce(c360.current_risk_rating, 3) AS risk,
         max(c.risk_score) AS max_score
  FROM {GOLD_SCHEMA}.sherlock_cases c
  JOIN {SILVER_SCHEMA}.customers cust ON cust.customer_id = c.customer_id
  LEFT JOIN {GOLD_SCHEMA}.customer_360 c360 ON c360.customer_id = c.customer_id
  GROUP BY c.customer_id, cust.full_name, cust.city, cust.country, c360.current_risk_rating
)
ORDER BY max_score DESC
LIMIT {int(limit)}
""")
    nodes, edges, seen = [], [], set()

    def add_node(nid, label, kind, score=None):
        if nid in seen:
            return
        seen.add(nid)
        nodes.append({"id": nid, "label": label, "kind": kind, "score": score})

    matched = []
    for s in seed:
        add_node(s["customer_id"], s["full_name"], "customer", s.get("risk"))
        matched.append({"name": s["full_name"], "kind": "CUSTOMER",
                        "detail": f"Customer: {s['full_name']} | {s.get('city') or ''} {s.get('country') or ''}",
                        "score": s.get("risk")})

    # Single query for ALL seed customers' accounts + counterparties (avoids the old
    # N+1: one warehouse round-trip instead of one per customer). Capped per customer
    # via row_number so the graph stays legible.
    seed_ids = [s["customer_id"] for s in seed]
    if seed_ids:
        binds = [{"name": f"c{i}", "value": cid} for i, cid in enumerate(seed_ids)]
        in_list = ", ".join(f":c{i}" for i in range(len(seed_ids)))
        rels = fetch_all(f"""
SELECT customer_id, account_id, counterparty_id, cp_name FROM (
  SELECT a.customer_id, a.account_id, t.counterparty_id, tp.full_name AS cp_name,
         row_number() OVER (PARTITION BY a.customer_id ORDER BY a.account_id, t.counterparty_id) AS rn
  FROM {SILVER_SCHEMA}.accounts a
  LEFT JOIN {SILVER_SCHEMA}.transactions t ON t.account_id = a.account_id
  LEFT JOIN {SILVER_SCHEMA}.third_parties tp ON tp.third_party_id = t.counterparty_id
  WHERE a.customer_id IN ({in_list})
) WHERE rn <= 12
""", binds)
        for r in rels:
            cid = r["customer_id"]
            if r.get("account_id"):
                aid = f"ACCT:{r['account_id']}"
                add_node(aid, r["account_id"], "account")
                edges.append({"source": cid, "target": aid, "edge_type": "owns_account"})
            if r.get("counterparty_id"):
                pid = f"CP:{r['counterparty_id']}"
                add_node(pid, r.get("cp_name") or r["counterparty_id"], "counterparty")
                edges.append({"source": cid, "target": pid, "edge_type": "transacts_with"})
    return {
        "nodes": nodes, "edges": edges,
        "node_count": len(nodes), "edge_count": len(edges),
        "matched_entities": matched[:10],
        "analysis": ("Showing the top high-risk customers and their direct connections. "
                     "Use the search bar to explore specific entities or patterns."),
        "query": q,
    }
