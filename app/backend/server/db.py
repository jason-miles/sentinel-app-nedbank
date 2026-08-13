"""Databricks SQL client via the Statement Execution API.

Reads/writes are governed by Unity Catalog and (in the app) stamped with the
service-principal identity. Mirrors the Valterra OM Portal db layer.
"""
import os
import time
from typing import Any, List, Dict, Optional
from databricks.sdk.service.sql import (
    StatementState,
    StatementResponse,
    StatementParameterListItem,
)

from .config import get_workspace_client, CATALOG

WAREHOUSE_ID = os.environ.get("FRAUD_WAREHOUSE_ID", "d0305022e6c3db8e")  # elexon-anamoly-app

# Single source of truth for the Mosaic AI model endpoint used by every GenAI
# surface (SAR multi-agent, triage, exec briefing, LLM-as-judge, Ask Sentinel
# fallbacks). Env-configurable so the served model can be swapped — e.g. to a
# newer Databricks foundation-model endpoint or a provisioned-throughput /
# fine-tuned serving endpoint — with zero code changes across all routes.
LLM_ENDPOINT = os.environ.get("FRAUD_LLM_ENDPOINT", "databricks-meta-llama-3-3-70b-instruct")


def _to_params(parameters: Optional[List[Dict]]):
    """Convert {name, value} dicts to typed StatementParameterListItem."""
    if not parameters:
        return None
    return [
        StatementParameterListItem(name=p["name"], value=p.get("value"))
        for p in parameters
    ]


def _execute(sql: str, parameters: Optional[List[Dict]] = None) -> StatementResponse:
    client = get_workspace_client()
    # 50s is the Statement Execution API max synchronous wait. ai_query() LLM calls
    # (multi-agent SAR) can take 10-40s; the old 30s wait risked a spurious timeout
    # on a single slow call. If a statement still isn't done at 50s the API returns
    # a PENDING handle rather than data — poll to completion below.
    resp = client.statement_execution.execute_statement(
        statement=sql,
        warehouse_id=WAREHOUSE_ID,
        parameters=_to_params(parameters),
        wait_timeout="50s",
        catalog=CATALOG,
    )
    # Poll if the warehouse returned before the statement finished (long ai_query).
    # Exponential backoff (0.4s → 2s cap) so a statement that finishes just after the
    # 50s wait returns almost immediately, instead of always eating a flat 2s tick.
    waited, delay = 0.0, 0.4
    while resp.status and resp.status.state in (StatementState.PENDING, StatementState.RUNNING) and waited < 120:
        time.sleep(delay)
        waited += delay
        delay = min(delay * 1.6, 2.0)
        resp = client.statement_execution.get_statement(resp.statement_id)
    return resp


def _require_success(resp: StatementResponse) -> None:
    """Raise a clear error unless the statement SUCCEEDED. Handles the case where
    the poll loop gave up while the statement was still PENDING/RUNNING (>120s) —
    resp.status(.state/.error) may then be None, so never dereference them blindly."""
    state = resp.status.state if resp.status else None
    if state != StatementState.SUCCEEDED:
        err = (resp.status.error if resp.status else None) or f"statement did not complete (state={state})"
        raise RuntimeError(f"SQL failed: {err}")


def fetch_all(sql: str, parameters: Optional[List[Dict]] = None) -> List[Dict[str, Any]]:
    resp = _execute(sql, parameters)
    _require_success(resp)
    if not resp.result or not resp.result.data_array or not resp.manifest or not resp.manifest.schema:
        return []
    cols = [c.name for c in resp.manifest.schema.columns]
    return [dict(zip(cols, row)) for row in resp.result.data_array]


def execute(sql: str, parameters: Optional[List[Dict]] = None) -> None:
    _require_success(_execute(sql, parameters))


def fetch_one(sql: str, parameters: Optional[List[Dict]] = None) -> Optional[Dict[str, Any]]:
    """Return the first row, or None. Shared so routes don't repeat the
    fetch-then-index idiom (pairs with the fetch_one_or_404 API helper)."""
    rows = fetch_all(sql, parameters)
    return rows[0] if rows else None


# ── Performance helpers ───────────────────────────────────────────────────
# Each Statement Execution API call carries ~1.5s of fixed round-trip overhead,
# so an endpoint that fires N independent SELECTs serially costs ~N×1.5s. These
# two helpers cut that: run independent queries concurrently, and cache the
# near-static reads (materialized-view dashboards) for a few seconds.

from concurrent.futures import ThreadPoolExecutor  # noqa: E402


def parallel(*tasks):
    """Run independent zero-arg callables concurrently and return their results
    in order. Used to collapse several independent warehouse round-trips in one
    endpoint into ~one round-trip of wall-clock time."""
    if not tasks:
        return []
    with ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        return [f.result() for f in [pool.submit(t) for t in tasks]]


# Daemon pool for fire-and-forget writes (e.g. audit-log INSERTs) so a ~1.5s
# warehouse round-trip never sits on the critical path of a user-facing GET.
_BG = ThreadPoolExecutor(max_workers=4, thread_name_prefix="sentinel-bg")


def fire_and_forget(fn) -> None:
    """Schedule a zero-arg callable on the background pool; never blocks or raises."""
    try:
        _BG.submit(fn)
    except Exception:  # pool shutdown / saturated — dropping a best-effort write is fine
        pass


_CACHE: Dict[str, tuple] = {}
_CACHE_TTL = float(os.environ.get("FRAUD_CACHE_TTL", "15"))  # seconds; 0 disables


def cached_fetch_all(key: str, sql: str, parameters: Optional[List[Dict]] = None,
                     ttl: Optional[float] = None) -> List[Dict[str, Any]]:
    """fetch_all with a tiny in-process TTL cache, keyed by `key`. For read-only,
    near-static dashboard queries a demo hammers repeatedly — the first hit pays
    the warehouse round-trip, subsequent hits within the TTL are instant. Safe
    because the underlying MVs change on the pipeline cadence, not per request."""
    life = _CACHE_TTL if ttl is None else ttl
    if life > 0:
        hit = _CACHE.get(key)
        if hit and (time.monotonic() - hit[0]) < life:
            return hit[1]
    rows = fetch_all(sql, parameters)
    if life > 0:
        _CACHE[key] = (time.monotonic(), rows)
    return rows


def ai_query(prompt: str) -> str:
    """Run one Mosaic AI inference against LLM_ENDPOINT and return the text.

    Single, safe entry point for every LLM call in the app. The prompt is always
    BOUND as a parameter — never string-interpolated into the SQL literal (Spark
    treats backslash as an escape char, so quote-doubling alone is injection-prone).
    """
    rows = fetch_all(
        "SELECT ai_query(:model, :prompt) AS a",
        [{"name": "model", "value": LLM_ENDPOINT}, {"name": "prompt", "value": prompt}],
    )
    return (rows[0]["a"] if rows else "") or ""
