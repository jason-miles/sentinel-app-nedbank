"""Capitec Fraud & AML — FastAPI application entry point.

Serves the built React frontend (frontend/dist) and the /api routes as a single
process (Databricks Apps binds one port; single-process avoids CORS).
"""
import os
import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from server.db import fetch_all, fire_and_forget
from server.routes import alerts, network, customers, travel, sherlock, genai, advanced_aml, sar_agents, sar_eval, sim

log = logging.getLogger("sentinel.app")


def _warm_warehouse():
    """Fire a trivial query so the serverless SQL warehouse is spun up before the
    first real demo click — turns a potential ~10-30s cold start into a warm ~1.5s."""
    try:
        fetch_all("SELECT 1")
    except Exception as e:  # never let warm-up break startup
        log.warning("warehouse warm-up failed: %s", e)


# Ping interval: comfortably under the warehouse auto-stop (20 min) so an idle app
# never lets its warehouse go cold and hand the next visitor a cold-start failure.
KEEP_WARM_SECS = int(os.environ.get("FRAUD_KEEP_WARM_SECS", "600"))


@asynccontextmanager
async def lifespan(_app: FastAPI):
    import asyncio
    # Prime the warehouse immediately (background so boot isn't blocked)...
    fire_and_forget(_warm_warehouse)

    # ...then keep it warm on a timer for as long as the app runs. A cold serverless
    # SQL warehouse was the cause of a "Couldn't load" failure after idle.
    async def _keeper():
        while True:
            await asyncio.sleep(KEEP_WARM_SECS)
            fire_and_forget(_warm_warehouse)
    task = asyncio.create_task(_keeper())
    try:
        yield
    finally:
        task.cancel()


app = FastAPI(title="SherlockAML — Nedbank", version="0.2.0", lifespan=lifespan)

# Compress JS/CSS/JSON responses over ~1KB (the Vite bundle + API payloads) so the
# first paint ships far fewer bytes. Streaming AI responses are chunked text and
# small, so gzip's minimum_size leaves them untouched.
app.add_middleware(GZipMiddleware, minimum_size=1024)

# CORS for local dev (Vite :5173 -> FastAPI :8000). Harmless in the app.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(alerts.router)
app.include_router(network.router)
app.include_router(customers.router)
app.include_router(travel.router)
app.include_router(sherlock.router)
app.include_router(genai.router)
app.include_router(advanced_aml.router)
app.include_router(sar_agents.router)
app.include_router(sar_eval.router)
app.include_router(sim.router)


@app.get("/api/health")
def health(warm: bool = False):
    """Liveness probe. `?warm=true` also touches the warehouse (fire-and-forget) so
    an uptime ping / pre-demo hit keeps the serverless SQL warehouse hot."""
    if warm:
        fire_and_forget(_warm_warehouse)
    return {"status": "ok", "app": "nedbank-sentinel"}


@app.get("/api/config")
def config():
    """Client config — dashboard embed target etc. (env-driven, account-portable)."""
    host = os.environ.get("DATABRICKS_HOST", "").rstrip("/")
    dash_id = os.environ.get("SENTINEL_DASHBOARD_ID", "")
    embed = f"{host}/embed/dashboardsv3/{dash_id}" if host and dash_id else ""
    return {"dashboard_id": dash_id, "dashboard_embed_url": embed,
            "dashboard_url": f"{host}/sql/dashboardsv3/{dash_id}" if host and dash_id else ""}


# Vite content-hashes every filename under /assets (e.g. index-B_N4zydP.js), so a
# given URL's bytes never change — serve them with a 1-year immutable cache so the
# browser reuses them across navigations and repeat demos instead of re-fetching.
class ImmutableStaticFiles(StaticFiles):
    def is_not_modified(self, response_headers, request_headers) -> bool:  # type: ignore[override]
        response_headers["Cache-Control"] = "public, max-age=31536000, immutable"
        return super().is_not_modified(response_headers, request_headers)

    async def get_response(self, path, scope):
        resp = await super().get_response(path, scope)
        resp.headers.setdefault("Cache-Control", "public, max-age=31536000, immutable")
        return resp


# Serve React frontend. Built artifacts live in webroot/ (a copy of
# frontend/dist under a name that `databricks sync` won't special-case, so the
# built UI ships to the app). Fall back to frontend/dist for local dev.
_HERE = os.path.dirname(__file__)
FRONTEND_DIR = os.path.join(_HERE, "webroot")
if not os.path.exists(FRONTEND_DIR):
    FRONTEND_DIR = os.path.join(_HERE, "frontend", "dist")
if os.path.exists(FRONTEND_DIR):
    app.mount("/assets", ImmutableStaticFiles(directory=os.path.join(FRONTEND_DIR, "assets")), name="assets")

    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        if full_path.startswith("api/"):
            return JSONResponse({"detail": "not found"}, status_code=404)
        # Serve root-level static files (favicon, logos, etc.) that Vite emits to
        # dist root from public/. Resolve the candidate and confirm it stays
        # INSIDE FRONTEND_DIR before serving — os.path.join discards the base on
        # an absolute full_path (e.g. '/etc/passwd'), and '..' alone isn't enough.
        if full_path:
            root = os.path.realpath(FRONTEND_DIR)
            candidate = os.path.realpath(os.path.join(root, full_path.lstrip("/")))
            if (candidate == root or candidate.startswith(root + os.sep)) and os.path.isfile(candidate):
                return FileResponse(candidate)
        return FileResponse(os.path.join(FRONTEND_DIR, "index.html"))
