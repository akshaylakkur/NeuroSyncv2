"""
NeuroSync Bridge Server — FastAPI app that runs the OpenClaw orchestrator
and exposes stress analysis results via REST API.
"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from orchestrator import Orchestrator, OrchestratorConfig
from orchestrator import social_api

logger = logging.getLogger("neurosync.api")


# ======================================================================
# API Models
# ======================================================================

class HealthResponse(BaseModel):
    status: str
    uptime_seconds: float
    version: str
    active_channels: list[str]
    poll_interval: float
    cycle_count: int


class AnalysisResponse(BaseModel):
    timestamp: str
    overall_stress_level: str
    total_messages: int
    total_unique_senders: int
    crisis_flag: bool
    total_urgent_items: int
    channel_breakdown: dict[str, Any]
    active_channels: list[str]
    cycle_number: int


class StatusResponse(BaseModel):
    running: bool
    cycle_count: int
    channel_count: int
    latest_analysis: AnalysisResponse | None
    message_counts: dict[str, int]


# ======================================================================
# App state
# ======================================================================

class AppState:
    orchestrator: Orchestrator | None = None
    start_time: datetime = datetime.now(timezone.utc)
    task: asyncio.Task | None = None


state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Start the orchestrator on boot, shut down on exit."""
    logger.info("NeuroSync API starting...")
    config = OrchestratorConfig.from_env()
    orchestrator = Orchestrator(config)

    state.orchestrator = orchestrator

    # Run orchestrator in background
    state.task = asyncio.create_task(orchestrator.start())

    yield

    # Shutdown
    logger.info("NeuroSync API shutting down...")
    if state.orchestrator:
        await state.orchestrator.stop()
    if state.task:
        state.task.cancel()
        try:
            await state.task
        except asyncio.CancelledError:
            pass


# ======================================================================
# FastAPI app
# ======================================================================

app = FastAPI(
    title="NeuroSync Orchestrator API",
    description="REST API for OpenClaw-powered message stress analysis",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ======================================================================
# Routes
# ======================================================================

@app.get("/health", response_model=HealthResponse)
async def health():
    """Health check endpoint."""
    o = state.orchestrator
    uptime = (datetime.now(timezone.utc) - state.start_time).total_seconds()

    return HealthResponse(
        status="running" if (o and o._running) else "stopped",
        uptime_seconds=round(uptime, 2),
        version="1.0.0",
        active_channels=[p.channel_name for p in (o._pollers if o else [])],
        poll_interval=o.config.global_poll_interval if o else 15.0,
        cycle_count=o._loop_count if o else 0,
    )


@app.get("/status", response_model=StatusResponse)
async def status():
    """Current orchestrator status with latest analysis."""
    o = state.orchestrator
    if not o:
        raise HTTPException(status_code=503, detail="Orchestrator not initialised")

    latest = await o.get_latest_analysis()
    msg_counts = {}
    if o._store:
        msg_counts = o._store.message_counts_by_channel(
            o.config.global_poll_interval * 2,
        )

    return StatusResponse(
        running=o._running,
        cycle_count=o._loop_count,
        channel_count=len(o._pollers),
        latest_analysis=AnalysisResponse(**latest) if latest else None,
        message_counts=msg_counts,
    )


@app.get("/analysis/latest", response_model=AnalysisResponse)
async def latest_analysis():
    """Get the most recent aggregated stress analysis."""
    o = state.orchestrator
    if not o:
        raise HTTPException(status_code=503, detail="Orchestrator not initialised")

    latest = await o.get_latest_analysis()
    if not latest:
        raise HTTPException(status_code=404, detail="No analysis available yet")

    return AnalysisResponse(**latest)


@app.get("/analysis/history")
async def analysis_history(limit: int = 10):
    """Get historical stress analyses."""
    o = state.orchestrator
    if not o:
        raise HTTPException(status_code=503, detail="Orchestrator not initialised")

    all_analyses = await o.get_all_analyses()
    return {"count": len(all_analyses), "analyses": all_analyses[-limit:]}


@app.get("/messages")
async def messages(
    channel: str | None = None,
    window: float | None = None,
):
    """Get recent polled messages, optionally filtered."""
    o = state.orchestrator
    if not o or not o._store:
        raise HTTPException(status_code=503, detail="Store not ready")

    msgs = o._store.get_messages(
        channel=channel,
        window_seconds=window or o.config.global_poll_interval * 4,
    )
    return {
        "count": len(msgs),
        "channel_filter": channel,
        "messages": msgs[-100:],
    }


@app.get("/channels")
async def channels():
    """List active polling channels."""
    o = state.orchestrator
    if not o:
        raise HTTPException(status_code=503, detail="Orchestrator not initialised")

    return {
        "channels": [
            {
                "name": p.channel_name,
                "type": type(p).__name__,
            }
            for p in o._pollers
        ],
        "count": len(o._pollers),
    }


@app.get("/metrics")
async def metrics():
    """Prometheus-style metrics endpoint."""
    o = state.orchestrator
    if not o:
        raise HTTPException(status_code=503, detail="Orchestrator not initialised")

    latest = await o.get_latest_analysis()
    msg_counts = {}
    if o._store:
        msg_counts = o._store.message_counts_by_channel(
            o.config.global_poll_interval * 2,
        )

    return {
        "neurosync_cycle_count": o._loop_count,
        "neurosync_running": 1 if o._running else 0,
        "neurosync_poll_interval_seconds": o.config.global_poll_interval,
        "neurosync_stress_level": latest.get("overall_stress_level", "none") if latest else "none",
        "neurosync_crisis_flag": 1 if (latest and latest.get("crisis_flag")) else 0,
        "neurosync_urgent_items": latest.get("total_urgent_items", 0) if latest else 0,
        "neurosync_total_messages": latest.get("total_messages", 0) if latest else 0,
        "neurosync_active_channels": len(o._pollers),
        **{f"neurosync_messages_{ch}": cnt for ch, cnt in msg_counts.items()},
    }


@app.get("/api/summary.txt")
async def summary_text():
    """Plain-text summary for easy reading."""
    o = state.orchestrator
    if not o:
        return {"error": "Not ready"}

    latest = await o.get_latest_analysis()
    if not latest:
        return {"error": "No data yet"}

    lines = [
        "NeuroSync Stress Analysis",
        f"Time: {latest.get('timestamp', '?')}",
        f"Cycle: #{latest.get('cycle_number', '?')}",
        f"Stress Level: {latest.get('overall_stress_level', '?').upper()}",
        f"Crisis: {'YES 🚨' if latest.get('crisis_flag') else 'No ✓'}",
        f"Messages: {latest.get('total_messages', 0)}",
        f"Urgent Items: {latest.get('total_urgent_items', 0)}",
        f"Channels: {', '.join(latest.get('active_channels', []))}",
    ]
    if latest.get("summary"):
        lines.append(f"Summary: {latest['summary']}")

    return {"text": "\n".join(lines)}


# ======================================================================
# Register Social Sentiment Routes
# ======================================================================

def _get_orchestrator():
    """Helper for social_api to access orchestrator state."""
    return state.orchestrator


social_api.register_social_routes(app, _get_orchestrator)