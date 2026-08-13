"""Advanced AML capabilities (market-gap features):
- Sanctions & watchlist screening hits
- Perpetual KYC dynamic customer risk
- Behavioral peer-group anomaly detection
"""
from typing import Optional
from fastapi import APIRouter
from ..db import fetch_all, cached_fetch_all
from ..config import GOLD_SCHEMA

router = APIRouter(prefix="/api/aml", tags=["advanced-aml"])


# ─────────────────────── Sanctions & Watchlist ───────────────────────────
@router.get("/screening")
def screening(confidence: Optional[str] = None, limit: int = 100):
    where = "1=1"
    params = []
    if confidence:
        where = "confidence = :conf"
        params = [{"name": "conf", "value": confidence}]
    # Unfiltered screening list is near-static and revisited often — cache it.
    # (The default view; filtered variants hit the warehouse directly.)
    sql = f"""
SELECT screening_id, entity_name, party_type, entity_country, watch_name, list_type,
       list_source, reason, severity, confidence, match_score
FROM {GOLD_SCHEMA}.sanctions_screening_hits
WHERE {where}
ORDER BY CASE confidence WHEN 'confirmed' THEN 0 WHEN 'probable' THEN 1 ELSE 2 END, match_score DESC
LIMIT {int(limit)}
"""
    if not confidence:
        return cached_fetch_all(f"screening/{int(limit)}", sql)
    return fetch_all(sql, params or None)


@router.get("/screening/summary")
def screening_summary():
    return cached_fetch_all("screening/summary", f"""
SELECT list_type, confidence, count(*) AS hits
FROM {GOLD_SCHEMA}.sanctions_screening_hits GROUP BY list_type, confidence
""")


# ─────────────────────── Model Governance ─────────────────────────────────
@router.get("/model-governance")
def model_governance():
    """Model risk management surface (regulators ask "how is the AI validated?").
    Returns the registered SAR model's validation metrics, the equal-alert-budget
    false-positive-reduction vs the legacy rules score, and governance metadata.
    Cached — training metadata only changes on a retrain, not per request."""
    rows = cached_fetch_all("model-governance", f"""
SELECT model_name, model_version, algorithm, run_id,
       roc_auc, precision, recall, f1,
       model_fp, rules_fp, fp_reduction_pct,
       n_features, n_labelled, positive_rate,
       blend_model_weight, blend_rules_weight, governance_status, trained_at
FROM {GOLD_SCHEMA}.ml_model_metrics
ORDER BY model_version DESC LIMIT 1
""", ttl=300)
    return rows[0] if rows else {}


@router.get("/model-drift")
def model_drift():
    """Feature-drift monitoring (ongoing model validation). Per-feature current-vs-
    baseline mean shift + status, and an overall verdict driving the retrain trigger."""
    rows = cached_fetch_all("model-drift", f"""
SELECT feature, baseline_mean, current_mean, mean_shift_sigma, drift_status, computed_at
FROM {GOLD_SCHEMA}.ml_drift_metrics
ORDER BY mean_shift_sigma DESC
""", ttl=300)
    status = "stable"
    if any(r.get("drift_status") == "drift" for r in rows):
        status = "drift"
    elif any(r.get("drift_status") == "warning" for r in rows):
        status = "warning"
    return {"overall_status": status, "features": rows}


# ─────────────────────── Audit Trail ──────────────────────────────────────
@router.get("/audit")
def audit_trail(case_id: Optional[str] = None, limit: int = 100):
    """Defensible audit trail — every case read, note, decision, and SAR action
    stamped with acting persona + timestamp."""
    where = "1=1"
    params = []
    if case_id:
        where = "case_id = :cid"
        params = [{"name": "cid", "value": case_id}]
    return fetch_all(f"""
SELECT event_ts, actor, action, case_id, detail, source
FROM {GOLD_SCHEMA}.audit_log
WHERE {where}
ORDER BY event_ts DESC
LIMIT {int(limit)}
""", params or None)


@router.get("/audit/summary")
def audit_summary():
    return fetch_all(f"""
SELECT action, count(*) AS events, max(event_ts) AS last_seen
FROM {GOLD_SCHEMA}.audit_log GROUP BY action ORDER BY events DESC
""")


# ─────────────────────── Perpetual KYC ────────────────────────────────────
@router.get("/pkyc")
def pkyc(min_risk: int = 0, limit: int = 100):
    return fetch_all(f"""
SELECT customer_id, full_name, segment, country, entity_id,
       dynamic_risk, risk_band, edd_review_required, risk_drivers,
       alert_count, severe_alerts, sanction_hits, media_hits
FROM {GOLD_SCHEMA}.pkyc_customer_risk
WHERE dynamic_risk >= {int(min_risk)}
ORDER BY dynamic_risk DESC
LIMIT {int(limit)}
""")


@router.get("/pkyc/summary")
def pkyc_summary():
    bands = fetch_all(f"""
SELECT risk_band, count(*) AS customers,
       sum(CASE WHEN edd_review_required THEN 1 ELSE 0 END) AS edd_required
FROM {GOLD_SCHEMA}.pkyc_customer_risk GROUP BY risk_band
""")
    return {"bands": bands}


@router.get("/pkyc/{customer_id}")
def pkyc_customer(customer_id: str):
    rows = fetch_all(f"""
SELECT * FROM {GOLD_SCHEMA}.pkyc_customer_risk WHERE customer_id = :cid
""", [{"name": "cid", "value": customer_id}])
    return rows[0] if rows else {"detail": "not found"}


# ─────────────────────── Peer-group anomaly ───────────────────────────────
@router.get("/anomalies")
def anomalies(limit: int = 100):
    return fetch_all(f"""
SELECT customer_id, full_name, segment, country, txn_count, peer_avg_txns,
       total_value, peer_avg_value, distinct_cps, anomaly_score, severity, explanation,
       z_txn_count, z_total_value, z_distinct_cps
FROM {GOLD_SCHEMA}.peer_anomaly
ORDER BY anomaly_score DESC
LIMIT {int(limit)}
""")


# ─────────────────────── Retrospective typology sweep ─────────────────────
@router.get("/typology-sweep")
def typology_sweep(typology: str = "tpp_gaming_layering", only_unalerted: bool = False,
                   limit: int = 100):
    """Proactive risk discovery (demo scenario C): given a published FATF typology,
    surface accounts whose behaviour matches it — including those that never tripped
    a monitoring rule. Flips the tool from reactive alert-handling to anticipation."""
    where = "typology = :typ"
    params = [{"name": "typ", "value": typology}]
    if only_unalerted:
        where += " AND never_alerted = true"
    return fetch_all(f"""
SELECT typology, customer_id, account_id, full_name, segment, declared_monthly_turnover,
       gaming_out, gaming_in, gaming_txns, roundtrip_ratio, net_flow, never_alerted, explanation
FROM {GOLD_SCHEMA}.typology_exposure
WHERE {where}
ORDER BY gaming_out DESC
LIMIT {int(limit)}
""", params)
