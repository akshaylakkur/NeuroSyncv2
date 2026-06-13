"""
NeuroSync Simulation Framework

Provides realistic message generation and simulated channel polling
for testing the NeuroSync orchestrator and iOS app without real
Discord/Gmail integrations.
"""

from .api import register_simulation_routes
from .generator import MessageGenerator, SimMessage, generate_1000_messages
from .poller import SimulatedPoller, SCENARIOS, BurstPattern

__all__ = [
    "register_simulation_routes",
    "MessageGenerator",
    "SimMessage",
    "generate_1000_messages",
    "SimulatedPoller",
    "SCENARIOS",
    "BurstPattern",
]