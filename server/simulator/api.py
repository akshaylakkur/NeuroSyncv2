"""
NeuroSync Simulation — HTTP Control API

Exposes endpoints to start/stop/configure the simulation and view its status.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from simulator.poller import SCENARIOS, SimulatedPoller

logger = logging.getLogger("neurosync.simulator.api")

# Global registry of active simulated pollers
_simulated_pollers: list[SimulatedPoller] = []
_simulation_active: bool = False
_simulation_config: dict[str, Any] = {
    "scenario": "normal_day",
    "seed": 42,
    "total_messages": 1000,
}


# ------------------------------------------------------------------
# Pydantic models
# ------------------------------------------------------------------

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


class SimStatusResponse(BaseModel):
    active: bool
    scenario: str
    seed: int
    total_messages: int
    channels: list[dict[str, Any]]
    available_scenarios: list[str]
    cycle_count: int


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def _get_pollers() -> list[SimulatedPoller]:
    return _simulated_pollers


def _register_poller(poller: SimulatedPoller) -> None:
    _simulated_pollers.append(poller)


def register_simulated_poller(poller: SimulatedPoller) -> None:
    """Public helper to register a simulated poller (e.g. from lifespan)."""
    _register_poller(poller)


def _clear_pollers() -> None:
    _simulated_pollers.clear()


# ------------------------------------------------------------------
# Route registration
# ------------------------------------------------------------------

def register_simulation_routes(app: FastAPI) -> None:
    """Register all simulation control endpoints on the FastAPI app."""

    @app.get("/sim/status", response_model=SimStatusResponse)
    async def sim_status() -> dict[str, Any]:
        """Get current simulation status."""
        channels = []
        total_cycles = 0
        for p in _simulated_pollers:
            channels.append({
                "name": p.channel_name,
                "scenario": p._scenario,
                "cycle_index": p._cycle_index,
                "remaining_pool": p._generator.remaining,
                "total_pool": p._generator.total,
            })
            total_cycles += p._cycle_index

        return {
            "active": _simulation_active,
            "scenario": _simulation_config.get("scenario", "none"),
            "seed": _simulation_config.get("seed", 0),
            "total_messages": _simulation_config.get("total_messages", 0),
            "channels": channels,
            "available_scenarios": list(SCENARIOS.keys()),
            "cycle_count": total_cycles,
        }

    @app.post("/sim/start")
    async def sim_start(req: SimStartRequest) -> dict[str, Any]:
        """Start or restart the simulation with a given scenario."""
        global _simulation_active, _simulation_config

        if req.scenario not in SCENARIOS:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown scenario '{req.scenario}'. Available: {list(SCENARIOS.keys())}",
            )

        _simulation_config = {
            "scenario": req.scenario,
            "seed": req.seed,
            "total_messages": req.total_messages,
        }

        # Stop existing pollers
        for p in _simulated_pollers:
            p.stop()
        _clear_pollers()

        # Create new pollers for each requested channel
        from simulator.generator import MessageGenerator
        gen = MessageGenerator(seed=req.seed)
        gen.generate_pool(req.total_messages)

        for ch_name in req.channels:
            from orchestrator.config import ChannelSettings
            settings = ChannelSettings(
                enabled=True,
                max_messages_per_poll=50,
                poll_interval_seconds=15,
            )
            poller = SimulatedPoller(
                channel_name=ch_name,
                settings=settings,
                generator=gen,
                scenario=req.scenario,
                seed=req.seed,
            )
            _register_poller(poller)
            logger.info("Created simulated poller for '%s' with scenario '%s'", ch_name, req.scenario)

        _simulation_active = True

        return {
            "status": "started",
            "scenario": req.scenario,
            "channels": req.channels,
            "total_messages": req.total_messages,
            "seed": req.seed,
        }

    @app.post("/sim/stop")
    async def sim_stop() -> dict[str, Any]:
        """Stop all simulated pollers."""
        global _simulation_active
        for p in _simulated_pollers:
            p.stop()
        _simulation_active = False
        return {"status": "stopped", "channels_stopped": len(_simulated_pollers)}

    @app.post("/sim/scenario")
    async def sim_change_scenario(scenario: str) -> dict[str, Any]:
        """Change the active scenario without restarting the simulation."""
        if scenario not in SCENARIOS:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown scenario '{scenario}'. Available: {list(SCENARIOS.keys())}",
            )
        for p in _simulated_pollers:
            p.set_scenario(scenario)
        _simulation_config["scenario"] = scenario
        return {"status": "scenario_changed", "scenario": scenario}

    @app.post("/sim/inject")
    async def sim_inject(req: SimInjectRequest) -> dict[str, Any]:
        """Inject a custom message into a simulated channel's next poll."""
        import uuid
        from datetime import datetime, timezone

        for p in _simulated_pollers:
            if p.channel_name == req.channel:
                # Prepend a custom message to be picked up next poll
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
                # Hack: insert at current position in the pool
                pool = p._generator._pool
                idx = max(0, p._generator._index - 1)
                pool.insert(idx, msg)
                return {"status": "injected", "channel": req.channel, "message_id": msg.id}

        raise HTTPException(
            status_code=404,
            detail=f"No simulated poller found for channel '{req.channel}'",
        )

    @app.get("/sim/scenarios")
    async def sim_scenarios() -> dict[str, Any]:
        """List all available simulation scenarios with descriptions."""
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
                    "avg_burst_size": sum((p.min_msgs + p.max_msgs) / 2 for p in patterns) / len(patterns),
                }
                for name, patterns in SCENARIOS.items()
            ]
        }
