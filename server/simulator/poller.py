"""
NeuroSync Simulation — Simulated Poller

Replaces real Discord/Gmail pollers with a message generator that feeds
realistic messages into the orchestrator at variable rates.
Supports multiple stress scenarios: normal day, incident escalation,
weekend calm, crisis spike, gradual build-up, etc.
"""

from __future__ import annotations

import asyncio
import logging
import random
from datetime import datetime, timezone
from typing import Any

from orchestrator.config import ChannelSettings
from orchestrator.poller import BasePoller
from simulator.generator import MessageGenerator

logger = logging.getLogger("neurosync.simulator")


# ------------------------------------------------------------------
# Scenarios
# ------------------------------------------------------------------

class BurstPattern:
    """Defines message burst behaviour for a single poll cycle."""

    def __init__(
        self,
        min_msgs: int = 0,
        max_msgs: int = 5,
        crisis_chance: float = 0.05,
        high_stress_chance: float = 0.2,
        positive_chance: float = 0.3,
    ) -> None:
        self.min_msgs = min_msgs
        self.max_msgs = max_msgs
        self.crisis_chance = crisis_chance
        self.high_stress_chance = high_stress_chance
        self.positive_chance = positive_chance


SCENARIOS: dict[str, list[BurstPattern]] = {
    # Normal work day: moderate traffic, occasional spikes
    "normal_day": [
        BurstPattern(2, 8, 0.02, 0.15, 0.35),
        BurstPattern(1, 5, 0.02, 0.15, 0.35),
        BurstPattern(3, 12, 0.05, 0.25, 0.25),  # morning standup
        BurstPattern(0, 4, 0.01, 0.10, 0.40),
        BurstPattern(2, 7, 0.02, 0.15, 0.35),
        BurstPattern(5, 20, 0.08, 0.30, 0.15),  # incident brewing
        BurstPattern(1, 6, 0.03, 0.20, 0.30),
        BurstPattern(0, 3, 0.01, 0.10, 0.45),
    ],
    # Incident escalation: starts calm, builds to crisis, then resolves
    "incident_escalation": [
        BurstPattern(1, 4, 0.01, 0.10, 0.40),   # calm
        BurstPattern(2, 6, 0.02, 0.15, 0.35),   # noticing issues
        BurstPattern(3, 10, 0.05, 0.25, 0.25),  # alerts firing
        BurstPattern(5, 25, 0.15, 0.40, 0.15),  # escalating
        BurstPattern(10, 50, 0.30, 0.50, 0.05), # CRISIS PEAK
        BurstPattern(8, 35, 0.25, 0.45, 0.08),  # still critical
        BurstPattern(5, 20, 0.15, 0.35, 0.15),  # mitigation in progress
        BurstPattern(3, 12, 0.08, 0.25, 0.25),  # improving
        BurstPattern(2, 8, 0.05, 0.20, 0.30),   # monitoring
        BurstPattern(1, 5, 0.02, 0.15, 0.35),   # post-mortem
        BurstPattern(0, 3, 0.01, 0.10, 0.45),   # back to normal
    ],
    # Weekend calm: very low traffic, mostly positive/neutral
    "weekend_calm": [
        BurstPattern(0, 2, 0.00, 0.05, 0.60),
        BurstPattern(0, 1, 0.00, 0.02, 0.70),
        BurstPattern(0, 3, 0.00, 0.08, 0.55),
        BurstPattern(0, 1, 0.00, 0.03, 0.65),
        BurstPattern(0, 2, 0.00, 0.05, 0.60),
    ],
    # Crisis spike: sudden massive burst then gradual decline
    "crisis_spike": [
        BurstPattern(0, 2, 0.01, 0.10, 0.40),   # baseline
        BurstPattern(0, 3, 0.02, 0.15, 0.35),
        BurstPattern(20, 80, 0.40, 0.55, 0.02), # SUDDEN SPIKE
        BurstPattern(15, 60, 0.35, 0.50, 0.05),
        BurstPattern(10, 40, 0.25, 0.40, 0.10),
        BurstPattern(5, 25, 0.15, 0.30, 0.20),
        BurstPattern(3, 15, 0.08, 0.20, 0.30),
        BurstPattern(1, 8, 0.03, 0.15, 0.35),
        BurstPattern(0, 4, 0.01, 0.10, 0.40),
    ],
    # Gradual build-up: slow increase in stress over time
    "gradual_buildup": [
        BurstPattern(0, 2, 0.01, 0.08, 0.45),   # very calm
        BurstPattern(1, 3, 0.01, 0.10, 0.42),
        BurstPattern(1, 4, 0.02, 0.12, 0.40),
        BurstPattern(2, 5, 0.02, 0.15, 0.38),
        BurstPattern(2, 6, 0.03, 0.18, 0.35),
        BurstPattern(3, 8, 0.05, 0.22, 0.32),
        BurstPattern(3, 10, 0.07, 0.28, 0.28),
        BurstPattern(4, 12, 0.10, 0.32, 0.25),
        BurstPattern(5, 15, 0.12, 0.35, 0.22),
        BurstPattern(6, 18, 0.15, 0.38, 0.20),  # peak
        BurstPattern(4, 12, 0.10, 0.30, 0.25),  # resolving
        BurstPattern(2, 8, 0.05, 0.20, 0.32),
        BurstPattern(1, 5, 0.03, 0.15, 0.38),
        BurstPattern(0, 3, 0.02, 0.10, 0.42),
    ],
    # Rollercoaster: alternating high and low stress periods
    "rollercoaster": [
        BurstPattern(1, 5, 0.03, 0.15, 0.35),   # normal
        BurstPattern(0, 2, 0.01, 0.08, 0.50),   # calm
        BurstPattern(8, 30, 0.20, 0.45, 0.10),  # spike!
        BurstPattern(2, 6, 0.05, 0.18, 0.32),   # recovering
        BurstPattern(0, 2, 0.01, 0.08, 0.50),   # calm again
        BurstPattern(6, 25, 0.18, 0.42, 0.12),  # another spike
        BurstPattern(1, 4, 0.03, 0.12, 0.40),   # recovering
        BurstPattern(10, 45, 0.25, 0.50, 0.05), # big spike
        BurstPattern(3, 10, 0.08, 0.22, 0.28),  # winding down
        BurstPattern(0, 3, 0.02, 0.10, 0.45),   # calm
    ],
    # Sustained high pressure: consistent high volume, high stress
    "sustained_pressure": [
        BurstPattern(8, 25, 0.15, 0.45, 0.12),
        BurstPattern(6, 22, 0.12, 0.42, 0.15),
        BurstPattern(9, 28, 0.18, 0.48, 0.10),
        BurstPattern(7, 24, 0.14, 0.44, 0.13),
        BurstPattern(8, 26, 0.16, 0.46, 0.11),
        BurstPattern(10, 30, 0.20, 0.50, 0.08),
        BurstPattern(7, 23, 0.13, 0.43, 0.14),
        BurstPattern(9, 27, 0.17, 0.47, 0.10),
    ],
}


class SimulatedPoller(BasePoller):
    """A poller that generates realistic simulated messages instead of
    calling real Discord/Gmail APIs.
    """

    def __init__(
        self,
        channel_name: str,
        settings: ChannelSettings,
        generator: MessageGenerator | None = None,
        scenario: str = "normal_day",
        seed: int = 42,
    ) -> None:
        super().__init__(channel_name, settings)
        self._channel_name = channel_name
        self._settings = settings
        self._generator = generator or MessageGenerator(seed=seed)
        self._scenario = scenario
        self._rng = random.Random(seed + hash(channel_name) % 10000)
        self._cycle_index = 0
        self._scenario_cycles = SCENARIOS.get(scenario, SCENARIOS["normal_day"])
        self._running = True

    def set_scenario(self, scenario: str) -> None:
        if scenario in SCENARIOS:
            self._scenario = scenario
            self._scenario_cycles = SCENARIOS[scenario]
            self._cycle_index = 0
            logger.info("SimulatedPoller '%s' switched to scenario '%s'", self._channel_name, scenario)
        else:
            logger.warning("Unknown scenario '%s', keeping '%s'", scenario, self._scenario)

    def reset_pool(self, total_messages: int = 1000) -> None:
        """Regenerate the message pool (e.g., after a full cycle through)."""
        self._generator.generate_pool(total_messages)
        self._cycle_index = 0
        logger.info("SimulatedPoller '%s' reset pool to %d messages", self._channel_name, total_messages)

    async def poll(self) -> list[dict[str, Any]]:
        if not self._running:
            return []

        # Pick a burst pattern for this cycle
        pattern = self._scenario_cycles[self._cycle_index % len(self._scenario_cycles)]
        self._cycle_index += 1

        # Random burst size within pattern bounds
        burst_size = self._rng.randint(pattern.min_msgs, pattern.max_msgs)

        if burst_size == 0:
            return []

        # Pull messages from the generator (do not filter by channel here;
        # the generator tags with 'discord'/'gmail' but we'll override to
        # the poller's channel_name when emitting raw dicts)
        batch = self._generator.next_batch(burst_size)

        # If pool exhausted, regenerate
        if len(batch) < burst_size and self._generator.remaining == 0:
            self.reset_pool(1000)
            extra = self._generator.next_batch(burst_size - len(batch))
            batch.extend(extra)

        # Convert SimMessage -> raw dicts for the orchestrator
        result = []
        now = datetime.now(timezone.utc)
        for msg in batch:
            # Give each message a fresh, realistic timestamp
            offset = self._rng.randint(0, 14)  # within last 15s
            ts = now.replace(second=offset)
            result.append({
                "id": msg.id,
                "text": msg.text,
                "sender": msg.sender,
                "channel": self._channel_name,
                "timestamp": ts.isoformat(),
                "raw_type": msg.raw_type,
                "metadata": {**msg.metadata, "simulated": True, "scenario": self._scenario},
            })

        if result:
            logger.info(
                "SimulatedPoller '%s' returned %d messages (scenario '%s', cycle %d)",
                self._channel_name, len(result), self._scenario, self._cycle_index,
            )

        return result

    def stop(self) -> None:
        self._running = False

    def start(self) -> None:
        self._running = True
