"""Customer 360 CDP view (PRD §9 page 4)."""
from typing import Optional
from fastapi import APIRouter
from ..db import fetch_all
from ..config import GOLD_SCHEMA

router = APIRouter(prefix="/api", tags=["customers"])


@router.get("/customers")
def list_customers(min_alerts: int = 0, limit: int = 100):
    """Customer 360 list, optionally filtered to those with alerts."""
    return fetch_all(f"""
SELECT customer_id, full_name, segment, city, country, entity_id,
       num_accounts, total_balance, current_risk_rating, recent_alerts
FROM {GOLD_SCHEMA}.customer_360
WHERE recent_alerts >= {int(min_alerts)}
ORDER BY recent_alerts DESC, total_balance DESC
LIMIT {int(limit)}
""")


@router.get("/customers/{customer_id}")
def customer_detail(customer_id: str):
    """Single customer 360 profile + their alerts + adverse-media analysis."""
    prof = fetch_all(f"""
SELECT * FROM {GOLD_SCHEMA}.customer_360 WHERE customer_id = :cid
""", [{"name": "cid", "value": customer_id}])
    if not prof:
        return {"detail": "not found"}
    profile = prof[0]
    eid = profile.get("entity_id")
    alerts = fetch_all(f"""
SELECT alert_id, alert_type, severity, triggered_at, score, explanation
FROM {GOLD_SCHEMA}.fraud_alerts WHERE primary_entity_id = :eid
ORDER BY triggered_at DESC
""", [{"name": "eid", "value": eid}]) if eid else []
    media = fetch_all(f"""
SELECT headline, source, published_at, risk_summary
FROM {GOLD_SCHEMA}.adverse_media_analysis WHERE entity_id = :eid
""", [{"name": "eid", "value": eid}]) if eid else []
    profile["alerts"] = alerts
    profile["adverse_media"] = media
    return profile
