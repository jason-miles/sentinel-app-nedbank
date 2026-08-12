"""Nedbank Fraud & AML — FastAPI application entry point.

Serves the built React frontend (frontend/dist) and the /api routes as a single
process (Databricks Apps binds one port; single-process avoids CORS).
"""
import os
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware

from server.routes import alerts, network, customers, travel, sherlock, genai, advanced_aml, sar_agents, sar_eval

app = FastAPI(title="SherlockAML — Nedbank", version="0.2.0")

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


@app.get("/api/health")
def health():
    return {"status": "ok", "app": "nedbank-sentinel"}


@app.get("/api/config")
def config():
    """Client config — dashboard embed target etc. (env-driven, account-portable)."""
    host = os.environ.get("DATABRICKS_HOST", "").rstrip("/")
    dash_id = os.environ.get("SENTINEL_DASHBOARD_ID", "")
    embed = f"{host}/embed/dashboardsv3/{dash_id}" if host and dash_id else ""
    return {"dashboard_id": dash_id, "dashboard_embed_url": embed,
            "dashboard_url": f"{host}/sql/dashboardsv3/{dash_id}" if host and dash_id else ""}


# Serve React frontend. Built artifacts live in webroot/ (a copy of
# frontend/dist under a name that `databricks sync` won't special-case, so the
# built UI ships to the app). Fall back to frontend/dist for local dev.
_HERE = os.path.dirname(__file__)
FRONTEND_DIR = os.path.join(_HERE, "webroot")
if not os.path.exists(FRONTEND_DIR):
    FRONTEND_DIR = os.path.join(_HERE, "frontend", "dist")
if os.path.exists(FRONTEND_DIR):
    app.mount("/assets", StaticFiles(directory=os.path.join(FRONTEND_DIR, "assets")), name="assets")

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
