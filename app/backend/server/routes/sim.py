"""Live-transaction simulation — the 'real-time' demo beat.

Inserts a fresh, high-risk case into sherlock_cases (as if a new suspicious
transaction just streamed in and tripped a rule), so the analyst queue / exec
dashboard reflect it within a second. This demonstrates the near-real-time hot
path without requiring the app SP to write to the Auto Loader landing volume or
trigger the Lakeflow pipeline (which needs extra privilege + a 1-2 min round-trip).
The seeded scenario mirrors the WOW-A mule typology so the story stays coherent.
"""
import logging
import uuid
from datetime import datetime
from fastapi import APIRouter
from ..db import fetch_all, execute
from ..config import GOLD_SCHEMA

router = APIRouter(prefix="/api/sim", tags=["sim"])
log = logging.getLogger("sentinel.sim")

# Rotating synthetic subjects (clearly fake) for repeated demo runs.
_SUBJECTS = [
    ("Sizwe Mthembu", "Cash Structuring Detection", 96, 74000.0),
    ("Anika Reddy", "Rapid Fund Movement", 98, 312000.0),
    ("Johan Steyn", "Third-Party Deposit Pattern", 91, 88500.0),
    ("Zodwa Nene", "PEP/Sanctions Alert", 99, 145000.0),
]


@router.post("/live-alert")
def live_alert():
    """Simulate a live incoming suspicious transaction -> a new high-priority case.
    Returns the new case so the UI can highlight it appearing in the queue."""
    # Keep the demo clean: prune older simulated cases so repeated runs (and Story Mode)
    # never pile up CASE-LIVE-* rows that inflate the queue / case-volume KPI.
    try:
        execute(f"""
DELETE FROM {GOLD_SCHEMA}.sherlock_cases
WHERE case_id LIKE 'CASE-LIVE-%'
  AND case_id NOT IN (
    SELECT case_id FROM {GOLD_SCHEMA}.sherlock_cases
    WHERE case_id LIKE 'CASE-LIVE-%' ORDER BY opened_at DESC LIMIT 2)
""", [])
    except Exception as e:  # non-fatal: a failed prune shouldn't block the demo insert
        log.warning("live-sim prune failed: %s", e)
    n = fetch_all(f"SELECT count(*) AS c FROM {GOLD_SCHEMA}.sherlock_cases")
    seq = int((n[0]["c"] if n else 0)) % len(_SUBJECTS)
    name, scenario, risk, amount = _SUBJECTS[seq]
    case_id = f"CASE-LIVE-{datetime.utcnow().strftime('%H%M%S')}"
    alert_num = 990000 + int(datetime.utcnow().strftime("%H%M%S"))
    cust_id = f"CUSTLIVE{uuid.uuid4().hex[:6].upper()}"
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.sherlock_cases
  (case_id, alert_num, customer_id, customer_name, scenario, priority, status,
   team_id, team_name, analyst_id, analyst_name, risk_score, amount, days_open,
   due_date, investigation_hours, opened_at)
VALUES (:cid, :an, :cust, :name, :scen, 'critical', 'new',
   'TEAM_TM', 'AML Transaction Monitoring', :aid, :aname, :risk, :amt, 0,
   date_add(current_date(), 2), 0.0, current_timestamp())
""", [{"name": "cid", "value": case_id}, {"name": "an", "value": str(alert_num)},
      {"name": "cust", "value": cust_id}, {"name": "name", "value": name},
      {"name": "scen", "value": scenario}, {"name": "aid", "value": "AN_SARAH"},
      {"name": "aname", "value": "Thandeka Nkosi"}, {"name": "risk", "value": str(risk)},
      {"name": "amt", "value": str(amount)}])
    # audit it like any real event
    try:
        execute(f"""
INSERT INTO {GOLD_SCHEMA}.audit_log (event_ts, actor, action, case_id, detail, source)
VALUES (current_timestamp(), 'stream', 'live_alert', :cid, :d, 'realtime_feed')
""", [{"name": "cid", "value": case_id},
      {"name": "d", "value": f"Live-streamed suspicious transaction — {scenario} (ZAR {amount:,.0f})"}])
    except Exception as e:  # audit is best-effort; the case insert already succeeded
        log.warning("live-sim audit INSERT failed (case=%s): %s", case_id, e)
    return {"ok": True, "case_id": case_id, "customer_name": name, "scenario": scenario,
            "priority": "critical", "risk_score": risk, "amount": amount}
