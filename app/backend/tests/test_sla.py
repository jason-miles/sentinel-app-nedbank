"""Unit tests for case SLA policy (roadmap #4)."""
from server.sla import sla_target_days, sla_status


def test_target_days_by_priority():
    assert sla_target_days("critical") == 7
    assert sla_target_days("high") == 14
    assert sla_target_days("medium") == 30
    assert sla_target_days("low") == 60
    assert sla_target_days("unknown") == 30  # default


def test_on_track():
    s = sla_status("medium", 5)   # 5 of 30 days
    assert s["status"] == "on_track"
    assert s["breached"] is False
    assert s["days_remaining"] == 25


def test_at_risk_near_target():
    s = sla_status("critical", 6)  # 6 of 7 -> >=80%
    assert s["status"] == "at_risk"
    assert s["breached"] is False


def test_breached():
    s = sla_status("critical", 20)  # over 7
    assert s["status"] == "breached"
    assert s["breached"] is True
    assert s["days_remaining"] < 0


def test_handles_bad_days_open():
    s = sla_status("high", None)
    assert s["days_open"] == 0
    assert s["breached"] is False
