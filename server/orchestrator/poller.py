"""Message pollers for Discord and Email (Gmail) channels via OpenClaw CLI."""

from __future__ import annotations

import asyncio
import json
import logging
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Any

from .config import DiscordSettings, EmailSettings, SimulatedSettings

logger = logging.getLogger("neurosync.poller")


class BasePoller(ABC):
    """Abstract base for a channel message poller."""

    def __init__(self, channel_name: str, settings: Any) -> None:
        self._channel_name = channel_name
        self._settings = settings

    @abstractmethod
    async def poll(self) -> list[dict[str, Any]]:
        """Poll for new messages. Returns a list of normalised message dicts.

        Each message dict should contain at minimum:
            - id: unique message identifier
            - text: message content / body
            - sender: sender identifier
            - channel: channel name
            - timestamp: ISO-8601 or Unix timestamp
        """
        ...

    @property
    def channel_name(self) -> str:
        return self._channel_name

    @staticmethod
    async def _run_cli(args: list[str], timeout: int = 15) -> str:
        """Run an openclaw CLI command and return stdout."""
        try:
            proc = await asyncio.create_subprocess_exec(
                "openclaw", *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=timeout,
            )
            if proc.returncode != 0:
                err = stderr.decode().strip()
                if err:
                    logger.warning("CLI stderr: %s", err)
                return ""
            return stdout.decode().strip()
        except asyncio.TimeoutError:
            logger.error("CLI command timed out: openclaw %s", " ".join(args))
            return ""
        except FileNotFoundError:
            logger.error("openclaw CLI not found. Install it first.")
            return ""
        except Exception as e:
            logger.error("CLI command failed: %s", e)
            return ""


class DiscordPoller(BasePoller):
    """Polls Discord messages via the openclaw CLI."""

    def __init__(self, settings: DiscordSettings) -> None:
        super().__init__(settings.channel_name, settings)
        self._settings: DiscordSettings = settings
        self._last_message_id: str | None = None

    async def poll(self) -> list[dict[str, Any]]:
        """Poll recent Discord messages using the openclaw message read CLI."""
        messages: list[dict[str, Any]] = []

        # Build CLI args
        args = [
            "message", "read",
            "--channel", "discord",
            "--limit", str(self._settings.max_messages_per_poll),
            "--json",
        ]

        raw = await self._run_cli(args)

        if not raw:
            return messages

        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning("Failed to parse Discord poll JSON output")
            return messages

        raw_messages: list[dict[str, Any]] = []
        if isinstance(data, list):
            raw_messages = data
        elif isinstance(data, dict):
            raw_messages = data.get("messages", data.get("result", [data]))
        else:
            return messages

        for msg in raw_messages:
            normalised = self._normalise_message(msg)
            if normalised:
                messages.append(normalised)

        # Track last ID for incremental tracking
        if messages:
            self._last_message_id = messages[-1].get("id", "")

        return messages

    def _normalise_message(self, raw: dict[str, Any]) -> dict[str, Any] | None:
        """Normalise a raw Discord message into a standardised format."""
        if not raw or not isinstance(raw, dict):
            return None

        msg_id = raw.get("id") or raw.get("messageId") or raw.get("_id")
        if not msg_id:
            return None

        content = raw.get("content") or raw.get("text") or raw.get("message", "")
        sender = raw.get("author") or raw.get("sender") or raw.get("from", {})
        if isinstance(sender, dict):
            sender = sender.get("username") or sender.get("name") or sender.get("id", "unknown")
        timestamp = raw.get("timestamp") or datetime.now(timezone.utc).isoformat()

        return {
            "id": str(msg_id),
            "text": str(content)[:2000],
            "sender": str(sender),
            "channel": "discord",
            "timestamp": timestamp,
            "raw_type": "discord",
            "metadata": {
                "channel_id": raw.get("channelId"),
                "guild_id": raw.get("guildId"),
                "mentions": raw.get("mentions", []),
                "attachments": raw.get("attachments", []),
                "message_type": raw.get("type", "default"),
            },
        }


class EmailPoller(BasePoller):
    """Polls email messages via the openclaw CLI.

    Note: Email (Gmail) support via CLI varies by openclaw version.
    This implementation also supports direct Gmail API calls.
    """

    def __init__(self, settings: EmailSettings) -> None:
        super().__init__(settings.channel_name, settings)
        self._settings: EmailSettings = settings

    async def poll(self) -> list[dict[str, Any]]:
        """Poll email messages.

        Attempts the CLI first; if the channel isn't set up, returns empty.
        """
        messages: list[dict[str, Any]] = []

        # Try CLI-based email reading if available
        args = [
            "message", "read",
            "--channel", "gmail",
            "--limit", str(self._settings.max_results),
            "--json",
        ]

        raw = await self._run_cli(args)

        if raw:
            try:
                data = json.loads(raw)
                raw_msgs = data if isinstance(data, list) else [data]
                for msg in raw_msgs:
                    nm = self._normalise_message(msg)
                    if nm:
                        messages.append(nm)
                return messages
            except json.JSONDecodeError:
                pass

        # Email channel may not be configured — that's okay
        logger.debug("No email messages (channel may not be configured)")
        return messages

    def _normalise_message(self, raw: dict[str, Any]) -> dict[str, Any] | None:
        """Normalise a raw email message."""
        if not raw or not isinstance(raw, dict):
            return None

        msg_id = raw.get("id") or raw.get("messageId") or raw.get("_id")
        if not msg_id:
            return None

        # Handle Gmail-like structure
        payload = raw.get("payload", raw)
        headers = {}
        if isinstance(payload, dict):
            hs = payload.get("headers", raw.get("headers", []))
            if isinstance(hs, list):
                headers = {h.get("name", "").lower(): h.get("value", "") for h in hs if isinstance(h, dict)}
            elif isinstance(hs, dict):
                headers = hs

        body = raw.get("body") or raw.get("text") or raw.get("snippet", "")
        subject = headers.get("subject", raw.get("subject", "(no subject)"))
        sender = headers.get("from", raw.get("from", raw.get("sender", "unknown")))
        timestamp = raw.get("timestamp") or raw.get("date") or headers.get("date", datetime.now(timezone.utc).isoformat())

        return {
            "id": str(msg_id),
            "text": f"Subject: {subject}\n\n{str(body)[:1800]}",
            "sender": str(sender),
            "channel": "gmail",
            "timestamp": str(timestamp),
            "raw_type": "gmail",
            "metadata": {
                "subject": subject,
                "from": sender,
                "to": headers.get("to", ""),
                "cc": headers.get("cc", ""),
            },
        }


def create_poller(
    channel_type: str,
    settings: DiscordSettings | EmailSettings | SimulatedSettings,
) -> BasePoller:
    """Factory: create the appropriate poller for *channel_type*."""
    # Simulated (HTTP) pollers
    if channel_type in ("discord_sim", "gmail_sim"):
        from .simulated_http_poller import SimulatedHttpPoller
        return SimulatedHttpPoller(channel_type, settings)  # type: ignore[arg-type]

    pollers = {
        "discord": DiscordPoller,
        "gmail": EmailPoller,
    }
    cls = pollers.get(channel_type)
    if cls is None:
        raise ValueError(f"Unsupported channel type: {channel_type}")
    return cls(settings)  # type: ignore[arg-type]