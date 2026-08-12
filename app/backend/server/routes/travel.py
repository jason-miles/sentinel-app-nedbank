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
    # Reconstruct the exact consecutive tap pair that breached the speed
    # threshold for each alert (mirrors detect_impossible_travel), rather than
    # "the 2 most recent taps" — so the drawn journey matches the alert even
    # when the card has later legitimate taps. Match on the arriving tap whose
    # timestamp equals the alert's triggered_at to the second (avoids the
    # micro/millisecond-precision mismatch between the stored TS and the API TS).
    for a in alerts:
        acct = a.get("account_id")
        if acct and a.get("triggered_at"):
            a["legs"] = fetch_all(f"""
WITH ordered AS (
  SELECT city, country, lat, lon, txn_ts, merchant,
         lag(city)     OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_city,
         lag(country)  OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_country,
         lag(lat)      OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_lat,
         lag(lon)      OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_lon,
         lag(txn_ts)   OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_ts,
         lag(merchant) OVER (PARTITION BY account_id ORDER BY txn_ts) AS prev_merchant
  FROM {SILVER_SCHEMA}.card_transactions
  WHERE account_id = :acct
),
hit AS (
  SELECT * FROM ordered
  WHERE prev_ts IS NOT NULL
    AND date_trunc('SECOND', txn_ts) = date_trunc('SECOND', CAST(:trig AS TIMESTAMP))
  LIMIT 1
)
-- legs[0] = arriving tap (destination), legs[1] = departing tap (origin).
SELECT city, country, lat, lon, txn_ts, merchant FROM hit
UNION ALL
SELECT prev_city, prev_country, prev_lat, prev_lon, prev_ts, prev_merchant FROM hit
""", [{"name": "acct", "value": acct}, {"name": "trig", "value": str(a["triggered_at"])}])
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
