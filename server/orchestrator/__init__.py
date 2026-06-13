"""
NeuroSync Orchestrator — OpenClaw-powered message polling & LLM stress analysis.

Automatically polls Discord and Email (via Gmail connector) every 15 seconds,
analyses message volume, content, metadata patterns using LLM, and generates
a running stress summary.
"""

__version__ = "1.0.0"

from .orchestrator import Orchestrator
from .config import OrchestratorConfig

__all__ = ["Orchestrator", "OrchestratorConfig"]