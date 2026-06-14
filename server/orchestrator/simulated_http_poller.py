"""
NeuroSync — HTTP-based simulated poller.

Polls a standalone simulator server via HTTP instead of calling the
OpenClaw CLI. When the simulator server is unreachable, returns empty
results gracefully so the orchestrator keeps running with no data.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any

import httpx

from .config import SimulatedSettings
from .poller import BasePoller

logger = logging.getLogger("neurosync.simulated_http_poller")


class SimulatedHttpPoller(BasePoller):
    """Polls a remote simulator server for generated messages.

    The simulator server (simulator_server.py) runs independently and
    exposes a REST API. This poller calls it each cycle. If the server
    is down, poll() returns an empty list — the orchestrator handles
    this gracefully.
    """

    def __init__(self, channel_name: str, settings: SimulatedSettings) -> None:
        super().__init__(channel_name, settings)
        self._settings: SimulatedSettings = settings
        self._client: httpx.AsyncClient | None = None

    async def _get_client(self) -> httpx.AsyncClient:
        """Lazy-init the HTTP client."""
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self._settings.simulator_url,
                timeout=httpx.Timeout(5.0),
            )
        return self._client

    async def poll(self) -> list[dict[str, Any]]:
        """Poll the simulator server for messages.

        Returns a list of normalised message dicts, or an empty list
        if the simulator server is unreachable.
        """
        try:
            client = await self._get_client()
            resp = await client.get(
                "/sim/poll/{}".format(self._channel_name),
                params={"limit": self._settings.max_messages_per_poll},
            )
            resp.raise_for_status()
            data = resp.json()
        except httpx.ConnectError:
            logger.debug(
                "Simulator server not reachable at %s — returning empty",
                self._settings.simulator_url,
            )
            return []
        except httpx.TimeoutException:
            logger.debug("Simulator server timed out — returning empty")
            return []
        except httpx.HTTPStatusError as e:
            logger.debug("Simulator server returned %s — returning empty", e.response.status_code)
            return []
        except json.JSONDecodeError:
            logger.warning("Simulator server returned invalid JSON — returning empty")
            return []
        except Exception as e:
            logger.debug("Error polling simulator: %s — returning empty", e)
            return []

        # data is expected to be a list of message dicts
        if not isinstance(data, list):
            logger.warning(
                "Simulator returned non-list type %s — returning empty",
                type(data).__name__,
            )
            return []

        # Normalise messages to match the format expected by the orchestrator
        messages: list[dict[str, Any]] = []
        for raw in data:
            normalised = self._normalise_message(raw)
            if normalised:
                messages.append(normalised)

        if messages:
            logger.info(
                "SimulatedHttpPoller '%s' received %d messages from simulator",
                self._channel_name, len(messages),
            )

        return messages

    def _normalise_message(self, raw: dict[str, Any]) -> dict[str, Any] | None:
        """Normalise a raw message from the simulator into the standard format."""
        if not raw or not isinstance(raw, dict):
            return None

        msg_id = raw.get("id") or raw.get("messageId") or raw.get("_id")
        if not msg_id:
            return None

        content = raw.get("content") or raw.get("text") or raw.get("message", "")
        sender = raw.get("author") or raw.get("sender") or raw.get("from", "simulator")
        if isinstance(sender, dict):
            sender = sender.get("username") or sender.get("name") or "simulator"
        timestamp = raw.get("timestamp") or datetime.now(timezone.utc).isoformat()

        return {
            "id": str(msg_id),
            "text": str(content)[:2000],
            "sender": str(sender),
            "channel": self._channel_name,
            "timestamp": str(timestamp),
            "raw_type": raw.get("raw_type", "simulated"),
            "metadata": {
                "simulated": True,
                "source": "simulator_server",
                **(raw.get("metadata") or {}),
            },
        }

    async def close(self) -> None:
        """Close the HTTP client."""
        if self._client:
            await self._client.aclose()
            self._client = None
