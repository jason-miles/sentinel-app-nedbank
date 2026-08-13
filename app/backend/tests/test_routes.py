"""Route smoke tests with a mocked DB layer (roadmap #5).

No warehouse required — server.db.fetch_all/execute are monkeypatched so we exercise
the FastAPI wiring, parameter handling, and response shaping in isolation.
"""
import pytest
from fastapi.testclient import TestClient

import server.db as db
import app as app_module


@pytest.fixture
def client(monkeypatch):
    # audit() and read endpoints go through fetch_all/execute — stub both.
    def fake_fetch_all(sql, params=None):
        if "audit_log" in sql:
            return [{"event_ts": "2026-07-20T10:00:00", "actor": "Sarah Chen",
                     "action": "case_open", "case_id": "CASE-SCR-1",
                     "detail": "Opened", "source": "investigation"}]
        if "ml_model_metrics" in sql:
            return [{"model_name": "m", "model_version": 2, "algorithm": "GBT",
                     "run_id": "r", "roc_auc": 0.65, "precision": 0.54, "recall": 0.33,
                     "f1": 0.41, "model_fp": 32, "rules_fp": 38, "fp_reduction_pct": 15.8,
                     "n_features": 10, "n_labelled": 660, "positive_rate": 0.286,
                     "blend_model_weight": 0.7, "blend_rules_weight": 0.3,
                     "governance_status": "validated", "trained_at": "2026-07-20"}]
        return []

    monkeypatch.setattr(db, "fetch_all", fake_fetch_all)
    # advanced_aml imported fetch_all by name — patch there too.
    import server.routes.advanced_aml as aml
    monkeypatch.setattr(aml, "fetch_all", fake_fetch_all)
    return TestClient(app_module.app)


def test_audit_endpoint(client):
    r = client.get("/api/aml/audit?limit=10")
    assert r.status_code == 200
    data = r.json()
    assert isinstance(data, list) and data[0]["actor"] == "Sarah Chen"


def test_model_governance_endpoint(client):
    r = client.get("/api/aml/model-governance")
    assert r.status_code == 200
    data = r.json()
    assert data["fp_reduction_pct"] == 15.8
    assert data["governance_status"] == "validated"


def test_healthz(client):
    # SPA fallthrough should serve something for an unknown non-api path,
    # while an unknown /api path should 404.
    assert client.get("/api/does-not-exist").status_code == 404


def test_queue_filters_bind_safely(monkeypatch):
    """Queue filters must be parameter-bound; invalid priority is ignored."""
    calls = []

    def capture(sql, params=None):
        calls.append((sql, params or []))
        return []  # KPIs/weekly/active all empty is fine for wiring

    import server.routes.sherlock as sh
    monkeypatch.setattr(sh, "fetch_all", capture)
    c = TestClient(app_module.app)

    # Valid priority + scenario → both bound as params on the active query.
    c.get("/api/sherlock/queue/AN_SARAH?priority=critical&scenario=Rapid%20Fund%20Movement")
    active = [(s, p) for s, p in calls if "sherlock_cases c" in s and "status <> 'closed'" in s]
    assert active, "active-alerts query not found"
    sql, params = active[-1]
    names = {x["name"]: x["value"] for x in params}
    assert names.get("prio") == "critical"
    assert names.get("scen") == "Rapid Fund Movement"
    assert ":prio" in sql and ":scen" in sql  # bound, not interpolated

    # Invalid priority → filter omitted (no prio param, no clause).
    calls.clear()
    c.get("/api/sherlock/queue/AN_SARAH?priority=DROP%20TABLE")
    active = [(s, p) for s, p in calls if "sherlock_cases c" in s and "status <> 'closed'" in s]
    sql, params = active[-1]
    assert all(x["name"] != "prio" for x in params)
    assert ":prio" not in sql


def test_missing_record_returns_404(monkeypatch):
    """A single-record GET for a non-existent id must return HTTP 404 (not a 200
    body of {"detail": "not found"}), so the client's fetch wrapper routes it to
    its error state. Guards the fetch_one_or_404 refactor."""
    monkeypatch.setattr(db, "fetch_all", lambda sql, params=None: [])
    c = TestClient(app_module.app)
    assert c.get("/api/customers/NOPE").status_code == 404
    assert c.get("/api/alerts/NOPE").status_code == 404


def test_parallel_helper_runs_and_orders():
    """parallel() runs callables concurrently and preserves result order."""
    import time as _t
    start = _t.time()
    out = db.parallel(lambda: (_t.sleep(0.2), "a")[1],
                      lambda: (_t.sleep(0.2), "b")[1],
                      lambda: (_t.sleep(0.2), "c")[1])
    assert out == ["a", "b", "c"]
    assert _t.time() - start < 0.5  # ~0.2s (parallel), not ~0.6s (serial)


def test_cached_fetch_all_hits_warehouse_once(monkeypatch):
    """cached_fetch_all serves repeat calls (same key) from cache within the TTL."""
    calls = []
    monkeypatch.setattr(db, "fetch_all", lambda sql, params=None: calls.append(1) or [{"n": 1}])
    db._CACHE.pop("t/key", None)
    r1 = db.cached_fetch_all("t/key", "SELECT 1", ttl=60)
    r2 = db.cached_fetch_all("t/key", "SELECT 1", ttl=60)
    assert r1 == r2 == [{"n": 1}]
    assert len(calls) == 1  # second call served from cache
    db._CACHE.pop("t/key", None)
