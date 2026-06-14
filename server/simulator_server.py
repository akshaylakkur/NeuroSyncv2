#!/usr/bin/env python3
"""
NeuroSync Standalone Simulator Server

Runs independently on port 8081, generating simulated Discord/Gmail messages
for the main NeuroSync server to consume. Start/stop independently to
control when data flows in demos.

Usage:
    python simulator_server.py
    python simulator_server.py --port 8081 --scenario crisis_spike
    python simulator_server.py --seed 99 --total-messages 2000
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Ensure the server/ directory is on the path so we can import sibling packages
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from simulator.generator import MessageGenerator
from simulator.poller import SCENARIOS, SimulatedPoller
from orchestrator.config import ChannelSettings

logger = logging.getLogger("neurosync.simulator_server")

# ======================================================================
# App state
# ======================================================================

DEFAULT_PORT = 8081


class SimulatorState:
    """Holds the active simulation state."""

    def __init__(self) -> None:
        self.generator: MessageGenerator | None = None
        self.pollers: dict[str, SimulatedPoller] = {}
        self.scenario: str = "normal_day"
        self.seed: int = 42
        self.total_messages: int = 1000
        self.active: bool = False


state = SimulatorState()


# ======================================================================
# Pydantic models
# ======================================================================

class SimStartRequest(BaseModel):
    scenario: str = "normal_day"
    seed: int = 42
    total_messages: int = 1000
    channels: list[str] = ["discord_sim", "gmail_sim"]


class SimInjectRequest(BaseModel):
    channel: str = "discord_sim"
    text: str
    sender: str = "simulator"
    category: str = "neutral"


# ======================================================================
# Simulation lifecycle
# ======================================================================

def _init_simulation(
    scenario: str = "normal_day",
    seed: int = 42,
    total_messages: int = 1000,
    channels: list[str] | None = None,
) -> None:
    """Initialise or re-initialise the simulation with the given parameters."""
    if channels is None:
        channels = ["discord_sim", "gmail_sim"]

    # Stop existing pollers
    for poller in state.pollers.values():
        poller.stop()
    state.pollers.clear()

    # Create message generator
    gen = MessageGenerator(seed=seed)
    gen.generate_pool(total_messages)

    # Create one SimulatedPoller per channel
    for ch_name in channels:
        settings = ChannelSettings(
            enabled=True,
            max_messages_per_poll=50,
            poll_interval_seconds=15,
        )
        poller = SimulatedPoller(
            channel_name=ch_name,
            settings=settings,
            generator=gen,
            scenario=scenario,
            seed=seed + hash(ch_name) % 10000,
        )
        state.pollers[ch_name] = poller
        logger.info("Created simulated poller '%s' with scenario '%s'", ch_name, scenario)

    state.generator = gen
    state.scenario = scenario
    state.seed = seed
    state.total_messages = total_messages
    state.active = True

    logger.info(
        "Simulation started: scenario=%s, seed=%d, messages=%d, channels=%s",
        scenario, seed, total_messages, channels,
    )


# ======================================================================
# FastAPI app
# ======================================================================

app = FastAPI(
    title="NeuroSync Simulator Server",
    description="Standalone message simulator for NeuroSync demos",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ------------------------------------------------------------------
# Health
# ------------------------------------------------------------------

@app.get("/health")
async def health():
    """Health check — used by the main server to detect availability."""
    return {
        "status": "ok",
        "active": state.active,
        "scenario": state.scenario,
        "channels": list(state.pollers.keys()),
    }


# ------------------------------------------------------------------
# GET /sim/poll/{channel_name} — called by the main server's SimulatedHttpPoller
# ------------------------------------------------------------------

@app.get("/sim/poll/{channel_name}")
async def sim_poll(channel_name: str, limit: int = 50):
    """Return the next batch of simulated messages for *channel_name*.

    This endpoint is called by the main server's SimulatedHttpPoller
    each poll cycle. Returns a JSON array of message dicts.
    """
    if not state.active:
        return []

    poller = state.pollers.get(channel_name)
    if poller is None:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown channel '{channel_name}'. Active: {list(state.pollers.keys())}",
        )

    messages = await poller.poll()

    # Respect the limit
    if limit and len(messages) > limit:
        messages = messages[:limit]

    return messages


# ------------------------------------------------------------------
# Simulation control API
# ------------------------------------------------------------------

@app.get("/sim/status")
async def sim_status():
    """Get current simulation status."""
    channels = []
    total_cycles = 0
    for name, p in state.pollers.items():
        channels.append({
            "name": name,
            "scenario": p._scenario,
            "cycle_index": p._cycle_index,
            "remaining_pool": p._generator.remaining if p._generator else 0,
            "total_pool": p._generator.total if p._generator else 0,
        })
        total_cycles += p._cycle_index

    return {
        "active": state.active,
        "scenario": state.scenario,
        "seed": state.seed,
        "total_messages": state.total_messages,
        "channels": channels,
        "available_scenarios": list(SCENARIOS.keys()),
        "cycle_count": total_cycles,
    }


@app.post("/sim/start")
async def sim_start(req: SimStartRequest):
    """Start or restart the simulation."""
    if req.scenario not in SCENARIOS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown scenario '{req.scenario}'. Available: {list(SCENARIOS.keys())}",
        )

    _init_simulation(
        scenario=req.scenario,
        seed=req.seed,
        total_messages=req.total_messages,
        channels=req.channels,
    )

    return {
        "status": "started",
        "scenario": req.scenario,
        "channels": req.channels,
        "total_messages": req.total_messages,
        "seed": req.seed,
    }


@app.post("/sim/stop")
async def sim_stop():
    """Stop all simulated pollers."""
    for poller in state.pollers.values():
        poller.stop()
    state.active = False
    return {"status": "stopped", "channels_stopped": len(state.pollers)}


@app.post("/sim/scenario")
async def sim_change_scenario(scenario: str):
    """Change the active scenario without restarting."""
    if scenario not in SCENARIOS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown scenario '{scenario}'. Available: {list(SCENARIOS.keys())}",
        )
    for poller in state.pollers.values():
        poller.set_scenario(scenario)
    state.scenario = scenario
    return {"status": "scenario_changed", "scenario": scenario}


@app.post("/sim/inject")
async def sim_inject(req: SimInjectRequest):
    """Inject a custom message into a simulated channel."""
    import uuid

    poller = state.pollers.get(req.channel)
    if poller is None:
        raise HTTPException(
            status_code=404,
            detail=f"No simulated poller for channel '{req.channel}'",
        )

    from simulator.generator import SimMessage
    msg = SimMessage(
        id=str(uuid.uuid4()),
        text=req.text,
        sender=req.sender,
        channel=req.channel,
        timestamp=datetime.now(timezone.utc).isoformat(),
        raw_type="simulated",
        metadata={"simulated": True, "category": req.category, "injected": True},
    )
    # Insert at current position in the pool
    pool = poller._generator._pool
    idx = max(0, poller._generator._index - 1)
    pool.insert(idx, msg)

    return {"status": "injected", "channel": req.channel, "message_id": msg.id}


@app.get("/sim/scenarios")
async def sim_scenarios():
    """List all available scenarios."""
    descriptions = {
        "normal_day": "Moderate traffic with occasional spikes. Mimics a typical workday.",
        "incident_escalation": "Starts calm, builds to crisis, then resolves. Full stress arc.",
        "weekend_calm": "Very low traffic, mostly positive/neutral messages.",
        "crisis_spike": "Sudden massive burst then gradual decline. Tests emergency response.",
        "gradual_buildup": "Slowly increasing stress over multiple cycles. Tests early detection.",
        "rollercoaster": "Alternating high/low stress periods. Tests volatility handling.",
        "sustained_pressure": "Consistent high volume and high stress. Tests endurance.",
    }
    return {
        "scenarios": [
            {
                "name": name,
                "cycles": len(patterns),
                "description": descriptions.get(name, ""),
                "avg_burst_size": sum(
                    (p.min_msgs + p.max_msgs) / 2 for p in patterns
                ) / len(patterns),
            }
            for name, patterns in SCENARIOS.items()
        ]
    }


# ======================================================================
# CLI entry point
# ======================================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="NeuroSync Standalone Simulator Server",
    )
    parser.add_argument("--port", "-p", type=int, default=DEFAULT_PORT, help="Port to listen on")
    parser.add_argument("--scenario", "-s", default="normal_day", help="Initial scenario")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument("--total-messages", "-n", type=int, default=1000, help="Total message pool size")
    parser.add_argument("--debug", "-d", action="store_true", help="Debug logging")
    args = parser.parse_args()

    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s.%(msecs)03d [%(levelname)-5s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )

    # Auto-start simulation on launch
    _init_simulation(
        scenario=args.scenario,
        seed=args.seed,
        total_messages=args.total_messages,
    )

    print("═" * 60)
    print("  NeuroSync Simulator Server")
    print("═" * 60)
    print(f"  Port          : {args.port}")
    print(f"  Scenario      : {args.scenario}")
    print(f"  Seed          : {args.seed}")
    print(f"  Message pool  : {args.total_messages}")
    print(f"  Channels      : {', '.join(state.pollers.keys())}")
    print("═" * 60)
    print(f"  Main server polls: http://localhost:{args.port}/sim/poll/<channel>")
    print(f"  Sim control API : http://localhost:{args.port}/sim/status")
    print("═" * 60)
    print("  Press Ctrl+C to stop.")
    print()

    uvicorn.run(app, host="0.0.0.0", port=args.port, log_level="info" if not args.debug else "debug")


if __name__ == "__main__":
    main()
