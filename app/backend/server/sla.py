"""Case SLA policy (NEXT_STEPS #4).

Pure, dependency-free so it is unit-testable and reused by the API. SLA target days
are driven by case priority (higher priority = tighter SLA). Breach status is computed
from days_open vs the target.
"""

# Priority -> SLA target (calendar days to resolution).
SLA_DAYS = {"critical": 7, "high": 14, "medium": 30, "low": 60}
DEFAULT_SLA_DAYS = 30


def sla_target_days(priority: str) -> int:
    return SLA_DAYS.get((priority or "").lower(), DEFAULT_SLA_DAYS)


def sla_status(priority: str, days_open) -> dict:
    """Return {target_days, days_open, days_remaining, breached, status}.
    status: 'breached' (over), 'at_risk' (>=80% of target), else 'on_track'."""
    target = sla_target_days(priority)
    try:
        d = int(days_open)
    except (TypeError, ValueError):
        d = 0
    remaining = target - d
    if d > target:
        status = "breached"
    elif d >= 0.8 * target:
        status = "at_risk"
    else:
        status = "on_track"
    return {"target_days": target, "days_open": d, "days_remaining": remaining,
            "breached": d > target, "status": status}
