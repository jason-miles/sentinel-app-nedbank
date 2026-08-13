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
    waited = 0.0
    while resp.status and resp.status.state in (StatementState.PENDING, StatementState.RUNNING) and waited < 120:
        time.sleep(2)
        waited += 2
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
