"""FastAPI server for HermesViz – serves analytics data as JSON."""

import os
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from .reader import (
    read_sessions, read_session_detail, read_overview,
    read_daily_stats, read_gateway_status, read_skills,
    read_cron_jobs, read_config, read_state_from_db
)

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

app = FastAPI(title="HermesViz", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─── API Routes ────────────────────────────────────────────────

@app.get("/api/overview")
async def api_overview():
    return read_overview()


@app.get("/api/sessions")
async def api_sessions(limit: int = 200, offset: int = 0):
    sessions = read_sessions()
    return {
        "total": len(sessions),
        "sessions": sessions[offset:offset + limit],
    }


@app.get("/api/sessions/{session_id}")
async def api_session_detail(session_id: str):
    detail = read_session_detail(session_id)
    if detail is None:
        return {"error": "Session not found"}, 404
    return detail


@app.get("/api/daily")
async def api_daily_stats():
    return read_daily_stats()


@app.get("/api/gateway")
async def api_gateway():
    gw = read_gateway_status()
    if gw is None:
        return {"error": "Gateway state not available"}
    return gw


@app.get("/api/skills")
async def api_skills():
    return read_skills()


@app.get("/api/cron")
async def api_cron():
    return read_cron_jobs()


@app.get("/api/config")
async def api_config():
    cfg = read_config()
    # Redact sensitive keys
    for section in cfg.values():
        if isinstance(section, dict):
            section.pop("api_key", None)
    return cfg


@app.get("/api/db-info")
async def api_db_info():
    return read_state_from_db()


# ─── Static Frontend ───────────────────────────────────────────

if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")

    @app.get("/")
    async def serve_frontend():
        return FileResponse(str(FRONTEND_DIR / "index.html"))


def start_server(host: str = "127.0.0.1", port: int = 18766):
    """Start the uvicorn server."""
    import uvicorn
    uvicorn.run(app, host=host, port=port, log_level="info")
