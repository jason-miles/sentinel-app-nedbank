"""Alert Queue, Alert Detail, and feedback write-back (PRD §9 pages 1-2, §7.3)."""
import uuid
from typing import Optional
from fastapi import APIRouter
from pydantic import BaseModel

from ..db import fetch_all, execute
from ..config import GOLD_SCHEMA

router = APIRouter(prefix="/api", tags=["alerts"])


# fraud_alerts is a pipeline MV the app cannot UPDATE, so effective triage status
# is the latest analyst feedback (if any) folded over the MV's default 'new'.
# This subquery is reused by the queue and detail endpoints.
_EFFECTIVE_STATUS_CTE = f"""
WITH latest_fb AS (
  SELECT alert_id, status, analyst_feedback, analyst, created_at FROM (
    SELECT alert_id, status, analyst_feedback, analyst, created_at,
           row_number() OVER (PARTITION BY alert_id ORDER BY created_at DESC) rn
    FROM {GOLD_SCHEMA}.alert_feedback
  ) WHERE rn = 1
)
"""


@router.get("/alerts")
def list_alerts(alert_type: Optional[str] = None, severity: Optional[str] = None,
                status: Optional[str] = None, limit: int = 200):
    """Filterable alert queue (page 1). Status reflects latest analyst feedback."""
    where = ["1=1"]
    params = []
    if alert_type:
        where.append("fa.alert_type = :alert_type")
        params.append({"name": "alert_type", "value": alert_type})
    if severity:
        where.append("fa.severity = :severity")
        params.append({"name": "severity", "value": severity})
    if status:
        # Filter on effective status (feedback status if present, else MV default).
        where.append("coalesce(fb.status, fa.status) = :status")
        params.append({"name": "status", "value": status})
    sql = f"""
{_EFFECTIVE_STATUS_CTE}
SELECT fa.alert_id, fa.alert_type, fa.severity, fa.primary_entity_id, fa.account_ids,
       fa.triggered_at, fa.score, fa.explanation,
       coalesce(fb.status, fa.status) AS status
FROM {GOLD_SCHEMA}.fraud_alerts fa
LEFT JOIN latest_fb fb ON fb.alert_id = fa.alert_id
WHERE {' AND '.join(where)}
ORDER BY CASE fa.severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1
                          WHEN 'medium' THEN 2 ELSE 3 END, fa.triggered_at DESC
LIMIT {int(limit)}
"""
    return fetch_all(sql, params or None)


@router.get("/alerts/summary")
def alert_summary():
    """Header tiles: counts by type + severity."""
    by_type = fetch_all(f"""
SELECT alert_type, count(*) AS cnt,
       sum(CASE WHEN severity='critical' THEN 1 ELSE 0 END) AS critical
FROM {GOLD_SCHEMA}.fraud_alerts GROUP BY alert_type ORDER BY cnt DESC
""")
    totals = fetch_all(f"""
SELECT count(*) AS total,
       sum(CASE WHEN severity='critical' THEN 1 ELSE 0 END) AS critical,
       count(DISTINCT primary_entity_id) AS entities
FROM {GOLD_SCHEMA}.fraud_alerts
""")
    return {"by_type": by_type, "totals": totals[0] if totals else {}}


@router.get("/alerts/{alert_id}")
def alert_detail(alert_id: str):
    """Full alert detail incl. evidence map + entity + latest feedback (page 2)."""
    rows = fetch_all(f"""
{_EFFECTIVE_STATUS_CTE}
SELECT fa.alert_id, fa.alert_type, fa.severity, fa.primary_entity_id, fa.related_entity_ids,
       fa.account_ids, fa.transaction_ids, fa.triggered_at, fa.score, fa.explanation,
       fa.evidence, coalesce(fb.status, fa.status) AS status
FROM {GOLD_SCHEMA}.fraud_alerts fa
LEFT JOIN latest_fb fb ON fb.alert_id = fa.alert_id
WHERE fa.alert_id = :alert_id
""", [{"name": "alert_id", "value": alert_id}])
    if not rows:
        return {"detail": "not found"}
    alert = rows[0]
    fb = fetch_all(f"""
SELECT status, analyst_feedback, analyst, created_at
FROM {GOLD_SCHEMA}.alert_feedback
WHERE alert_id = :alert_id ORDER BY created_at DESC LIMIT 5
""", [{"name": "alert_id", "value": alert_id}])
    alert["feedback_history"] = fb
    return alert


class Feedback(BaseModel):
    alert_id: str
    status: str            # confirmed | dismissed | reviewing
    reason: str = ""
    analyst: str = "demo_analyst"


@router.post("/alerts/feedback")
def submit_feedback(fb: Feedback):
    """Analyst confirm/dismiss + reason -> alert_feedback write-back (feedback loop)."""
    execute(f"""
INSERT INTO {GOLD_SCHEMA}.alert_feedback
  (feedback_id, alert_id, status, analyst_feedback, analyst, created_at)
VALUES (:fid, :alert_id, :status, :reason, :analyst, current_timestamp())
""", [
        {"name": "fid", "value": str(uuid.uuid4())},
        {"name": "alert_id", "value": fb.alert_id},
        {"name": "status", "value": fb.status},
        {"name": "reason", "value": fb.reason},
        {"name": "analyst", "value": fb.analyst},
    ])
    return {"ok": True}
