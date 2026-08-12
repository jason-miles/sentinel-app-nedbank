"""Databricks SQL client via the Statement Execution API.

Reads/writes are governed by Unity Catalog and (in the app) stamped with the
service-principal identity. Mirrors the Valterra OM Portal db layer.
"""
import os
from typing import Any, List, Dict, Optional
from databricks.sdk.service.sql import (
    StatementState,
    StatementResponse,
    StatementParameterListItem,
)

from .config import get_workspace_client, CATALOG

WAREHOUSE_ID = os.environ.get("FRAUD_WAREHOUSE_ID", "d0305022e6c3db8e")  # elexon-anamoly-app


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
    import time
    waited = 0.0
    while resp.status and resp.status.state in (StatementState.PENDING, StatementState.RUNNING) and waited < 120:
        time.sleep(2)
        waited += 2
        resp = client.statement_execution.get_statement(resp.statement_id)
    return resp


def fetch_all(sql: str, parameters: Optional[List[Dict]] = None) -> List[Dict[str, Any]]:
    resp = _execute(sql, parameters)
    if resp.status.state != StatementState.SUCCEEDED:
        raise RuntimeError(f"SQL failed: {resp.status.error}")
    if not resp.result or not resp.result.data_array:
        return []
    cols = [c.name for c in resp.manifest.schema.columns]
    return [dict(zip(cols, row)) for row in resp.result.data_array]


def execute(sql: str, parameters: Optional[List[Dict]] = None) -> None:
    resp = _execute(sql, parameters)
    if resp.status.state != StatementState.SUCCEEDED:
        raise RuntimeError(f"SQL failed: {resp.status.error}")
