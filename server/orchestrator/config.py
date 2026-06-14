"""Configuration for the NeuroSync OpenClaw orchestrator."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


def _env_or_default(key: str, default: str) -> str:
    """Read an env var, falling back to *default*."""
    return os.environ.get(key, default)


@dataclass
class ChannelSettings:
    """Settings for a single polled channel."""

    enabled: bool = True
    max_messages_per_poll: int = 50
    poll_interval_seconds: int = 15


@dataclass
class LLMSettings:
    """Settings for the LLM stress-analysis engine."""

    model: str = "openai/gpt-4o-mini"
    temperature: float = 0.2
    max_tokens: int = 2048
    summary_window_seconds: int = 300  # 5-minute rolling window
    enable_sentiment: bool = True
    enable_urgency_detection: bool = True
    enable_topic_classification: bool = True
    enable_crisis_detection: bool = True
    enable_volume_anomaly: bool = True

    # Agent prompt template for stress analysis
    analysis_prompt_template: str = (
        "You are a communications stress analyser. "
        "Analyse the following batch of channel messages and produce a concise "
        "stress/urgency summary.\n\n"
        "Metadata summary:\n"
        "- Channel: {channel_name}\n"
        "- Time window: {time_window}\n"
        "- Total messages: {message_count}\n"
        "- Unique senders: {unique_senders}\n"
        "- Message rate: {message_rate} msgs/min\n\n"
        "Messages:\n{message_texts}\n\n"
        "Provide:\n"
        "1. OVERALL_STRESS_LEVEL: (none | low | moderate | high | critical)\n"
        "2. URGENT_ITEMS: List any messages requiring immediate attention\n"
        "3. VOLUME_TREND: (rising | stable | falling)\n"
        "4. TOP_THEMES: Key topics detected\n"
        "5. SENTIMENT: Overall sentiment trend\n"
        "6. CRISIS_FLAG: (yes | no) — is there a crisis or escalation?\n"
        "7. SUMMARY: 2-3 sentence synthesis"
    )


@dataclass
class DiscordSettings(ChannelSettings):
    """Discord-specific channel settings."""

    channel_name: str = "discord"
    guild_id: str | None = None
    allow_from: str = "all"  # 'all', 'contacts', 'allowlist'


@dataclass
class EmailSettings(ChannelSettings):
    """Email-specific channel settings (Gmail)."""

    channel_name: str = "gmail"
    query_filter: str = ""  # Optional Gmail query e.g. "is:unread"
    max_results: int = 20


@dataclass
class GatewaySettings:
    """Connection settings for the OpenClaw gateway."""

    ws_url: str = "ws://127.0.0.1:18789"
    api_key: str = ""
    mode: str = "local"
    connection_timeout: float = 10.0
    retry_attempts: int = 3

    def __post_init__(self) -> None:
        if not self.api_key:
            self.api_key = _env_or_default("OPENCLAW_GATEWAY_TOKEN", "")
        if not self.api_key:
            self.api_key = _env_or_default("OPENCLAW_API_KEY", "")


@dataclass
class SimulatedSettings:
    """Settings for simulated (HTTP-based) pollers."""

    enabled: bool = False
    channel_names: list[str] = field(default_factory=lambda: ["discord_sim", "gmail_sim"])
    simulator_url: str = "http://localhost:8081"
    max_messages_per_poll: int = 50


@dataclass
class StorageSettings:
    """Settings for storing poll results and summaries."""

    output_dir: str = "."
    save_raw_messages: bool = True
    save_summaries: bool = True
    max_history_messages: int = 10000
    summary_file: str = "stress_summary.json"
    raw_log_file: str = "message_log.jsonl"


@dataclass
class OrchestratorConfig:
    """Top-level configuration for the NeuroSync orchestrator."""

    gateway: GatewaySettings = field(default_factory=GatewaySettings)
    discord: DiscordSettings = field(default_factory=DiscordSettings)
    email: EmailSettings = field(default_factory=EmailSettings)
    simulated: SimulatedSettings = field(default_factory=SimulatedSettings)
    llm: LLMSettings = field(default_factory=LLMSettings)
    storage: StorageSettings = field(default_factory=StorageSettings)
    global_poll_interval: float = 15.0  # seconds
    debug: bool = False

    @classmethod
    def from_env(cls) -> OrchestratorConfig:
        """Build config from environment variables (prefixed with NEUROSYNC_)."""
        cfg = cls()
        env = os.environ

        # Gateway
        cfg.gateway.ws_url = env.get("NEUROSYNC_GW_URL", cfg.gateway.ws_url)
        cfg.gateway.api_key = env.get("NEUROSYNC_GW_TOKEN", cfg.gateway.api_key)
        cfg.gateway.mode = env.get("NEUROSYNC_GW_MODE", cfg.gateway.mode)

        # Discord
        cfg.discord.enabled = env.get("NEUROSYNC_DISCORD_ENABLED", "true").lower() == "true"
        cfg.discord.guild_id = env.get("NEUROSYNC_DISCORD_GUILD_ID", None)
        cfg.discord.max_messages_per_poll = int(
            env.get("NEUROSYNC_DISCORD_MAX_MSGS", str(cfg.discord.max_messages_per_poll))
        )

        # Email
        cfg.email.enabled = env.get("NEUROSYNC_EMAIL_ENABLED", "true").lower() == "true"
        cfg.email.query_filter = env.get("NEUROSYNC_EMAIL_QUERY", "")
        cfg.email.max_results = int(
            env.get("NEUROSYNC_EMAIL_MAX_RESULTS", str(cfg.email.max_results))
        )

        # Simulated (HTTP) pollers
        cfg.simulated.enabled = env.get("NEUROSYNC_SIM_MODE", "false").lower() == "true"
        cfg.simulated.simulator_url = env.get(
            "NEUROSYNC_SIMULATOR_URL", cfg.simulated.simulator_url
        )
        sim_channels = env.get("NEUROSYNC_SIM_CHANNELS")
        if sim_channels:
            cfg.simulated.channel_names = [ch.strip() for ch in sim_channels.split(",")]

        # When simulation mode is on, auto-disable real channels
        if cfg.simulated.enabled:
            if "NEUROSYNC_DISCORD_ENABLED" not in env:
                cfg.discord.enabled = False
            if "NEUROSYNC_EMAIL_ENABLED" not in env:
                cfg.email.enabled = False

        # LLM
        cfg.llm.model = env.get("NEUROSYNC_LLM_MODEL", cfg.llm.model)

        # Poll interval
        cfg.global_poll_interval = float(
            env.get("NEUROSYNC_POLL_INTERVAL", str(cfg.global_poll_interval))
        )
        cfg.debug = env.get("NEUROSYNC_DEBUG", "false").lower() == "true"

        return cfg


def load_config(config_path: str | Path | None = None) -> OrchestratorConfig:
    """Load configuration from a JSON/YAML file, or fall back to env defaults."""
    cfg = OrchestratorConfig.from_env()

    if config_path is not None:
        path = Path(config_path)
        if path.suffix in (".json",):
            import json
            with open(path) as f:
                data: dict[str, Any] = json.load(f)
            _apply_dict(cfg, data)
        elif path.suffix in (".yaml", ".yml"):
            try:
                import yaml
                with open(path) as f:
                    data = yaml.safe_load(f) or {}
                _apply_dict(cfg, data)
            except ImportError:
                raise RuntimeError("PyYAML is required for YAML config files. pip install pyyaml")

    return cfg


def _apply_dict(cfg: OrchestratorConfig, data: dict[str, Any]) -> None:
    """Apply a nested dict to a dataclass config recursively."""
    for key, value in data.items():
        if hasattr(cfg, key):
            field_val = getattr(cfg, key)
            if isinstance(field_val, (DiscordSettings, EmailSettings, SimulatedSettings,
                                      LLMSettings, GatewaySettings, StorageSettings)):
                if isinstance(value, dict):
                    for sub_key, sub_val in value.items():
                        if hasattr(field_val, sub_key):
                            setattr(field_val, sub_key, sub_val)
            else:
                setattr(cfg, key, value)