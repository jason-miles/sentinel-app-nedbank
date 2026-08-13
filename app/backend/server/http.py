"""Small HTTP helpers shared by the API routes.

Centralizes the fetch-then-404 idiom that was duplicated across ~8 endpoints.
Returning a real 404 (instead of HTTP 200 with a {"detail": "not found"} body)
lets the React client's fetch wrapper — which throws on !res.ok — route a missing
record to its error state instead of trying to render an error object as data.
"""
from typing import Any, Dict, Iterable, List, Optional
from fastapi import HTTPException
from fastapi.responses import StreamingResponse

from . import db  # call db.fetch_all via module ref so test monkeypatches are honored


def fetch_one_or_404(sql: str, parameters: Optional[List[Dict]] = None,
                     detail: str = "not found") -> Dict[str, Any]:
    """First row of the query, or raise HTTP 404. Use for single-record GETs."""
    rows = db.fetch_all(sql, parameters)
    if not rows:
        raise HTTPException(status_code=404, detail=detail)
    return rows[0]


def text_stream(chunks: Iterable[str]) -> StreamingResponse:
    """Stream plain-text token chunks to the client as they are produced. Sent as
    text/plain so the frontend can append each chunk directly (no SSE parsing) and
    the panel fills in live. Buffering is disabled so tokens aren't held back."""
    def _gen():
        for c in chunks:
            if c:
                yield c
    return StreamingResponse(_gen(), media_type="text/plain; charset=utf-8",
                             headers={"X-Accel-Buffering": "no", "Cache-Control": "no-cache"})
