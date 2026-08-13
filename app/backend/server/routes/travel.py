"""Impossible-travel map (PRD §9 page 6) and Reports (page 5)."""
from fastapi import APIRouter
from ..db import fetch_all
from ..config import GOLD_SCHEMA, SILVER_SCHEMA

router = APIRouter(prefix="/api", tags=["travel", "reports"])


@router.get("/impossible-travel")
def impossible_travel():
    """Flagged card journeys with from/to coords + implied speed for the map.

    Reconstructs the two legs behind each impossible_travel alert from
    silver.card_transactions so the map can draw the journey.
    """
    alerts = fetch_all(f"""
SELECT alert_id, account_ids[0] AS account_id, triggered_at, score, explanation,
       evidence['from_city'] AS from_city, evidence['to_city'] AS to_city,
       evidence['implied_kmh'] AS implied_kmh
FROM {GOLD_SCHEMA}.fraud_alerts
WHERE alert_type = 'impossible_travel'
ORDER BY triggered_at DESC
""")
    if not alerts:
        return alerts

    # Reconstruct the exact consecutive tap pair that breached the speed threshold
    # for each alert (mirrors detect_impossible_travel) — the arriving tap whose
    # timestamp equals the alert's triggered_at to the second (avoids the micro/
    # millisecond-precision mismatch between the stored TS and the API TS). ONE
    # windowed query joined to every alert, instead of the old query-per-alert
    # (N+1): a single warehouse round-trip regardless of alert count.
    ids = [a["account_id"] for a in alerts if a.get("account_id")]
    legs_by_alert: dict = {}
    if ids:
        binds = [{"name": f"a{i}", "value": v} for i, v in enumerate(ids)]
        in_list = ", ".join(f":a{i}" for i in range(len(ids)))
        rows = fetch_all(f"""
WITH ordered AS (
  SELECT account_id, city, country, lat, lon, txn_ts, merchant,
         lag(city)     OVER w AS prev_city,
         lag(country)  OVER w AS prev_country,
         lag(lat)      OVER w AS prev_lat,
         lag(lon)      OVER w AS prev_lon,
         lag(txn_ts)   OVER w AS prev_ts,
         lag(merchant) OVER w AS prev_merchant
  FROM {SILVER_SCHEMA}.card_transactions
  WHERE account_id IN ({in_list})
  WINDOW w AS (PARTITION BY account_id ORDER BY txn_ts)
),
hit AS (
  SELECT a.alert_id, o.*
  FROM {GOLD_SCHEMA}.fraud_alerts a
  JOIN ordered o
    ON o.account_id = a.account_ids[0]
   AND o.prev_ts IS NOT NULL
   AND date_trunc('SECOND', o.txn_ts) = date_trunc('SECOND', a.triggered_at)
  WHERE a.alert_type = 'impossible_travel'
)
-- leg_order 0 = arriving tap (destination), 1 = departing tap (origin).
SELECT alert_id, 0 AS leg_order, city, country, lat, lon, txn_ts, merchant FROM hit
UNION ALL
SELECT alert_id, 1 AS leg_order, prev_city, prev_country, prev_lat, prev_lon, prev_ts, prev_merchant FROM hit
ORDER BY alert_id, leg_order
""", binds)
        for r in rows:
            leg = {k: r[k] for k in ("city", "country", "lat", "lon", "txn_ts", "merchant")}
            legs_by_alert.setdefault(r["alert_id"], []).append(leg)

    for a in alerts:
        a["legs"] = legs_by_alert.get(a["alert_id"], [])
    return alerts


@router.get("/reports/weekly")
def weekly_report():
    """Genie-style narrative numbers for the weekly report (PRD §7.2)."""
    return fetch_all(f"""
SELECT alert_type, count(*) AS this_week,
       sum(CASE WHEN severity='critical' THEN 1 ELSE 0 END) AS critical
FROM {GOLD_SCHEMA}.fraud_alerts
WHERE triggered_at >= current_timestamp() - INTERVAL 7 DAYS
GROUP BY alert_type ORDER BY this_week DESC
""")
