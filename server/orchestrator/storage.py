"""Persistent storage for polled messages and stress summaries."""

from __future__ import annotations

import json
import logging
from collections import defaultdict, deque
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any

from .config import StorageSettings

logger = logging.getLogger("neurosync.storage")


class RollingBuffer:
    """Thread-safe rolling buffer with a maximum size."""

    def __init__(self, maxlen: int) -> None:
        self._deque: deque[dict[str, Any]] = deque(maxlen=maxlen)
        self._lock = Lock()

    def append(self, item: dict[str, Any]) -> None:
        with self._lock:
            self._deque.append(item)

    def extend(self, items: list[dict[str, Any]]) -> None:
        with self._lock:
            for item in items:
                self._deque.append(item)

    def get_all(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._deque)

    def __len__(self) -> int:
        with self._lock:
            return len(self._deque)

    def clear(self) -> None:
        with self._lock:
            self._deque.clear()

    def get_since(self, cutoff_ts: float) -> list[dict[str, Any]]:
        """Return all messages with timestamp >= *cutoff_ts*."""
        result: list[dict[str, Any]] = []
        with self._lock:
            for item in self._deque:
                ts = item.get("timestamp", 0.0)
                if isinstance(ts, (int, float)) and ts >= cutoff_ts:
                    result.append(item)
                elif isinstance(ts, str):
                    # Try parsing ISO string
                    try:
                        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                        if dt.timestamp() >= cutoff_ts:
                            result.append(item)
                    except (ValueError, TypeError):
                        result.append(item)
        return result


class MessageStore:
    """Stores raw polled messages and computed stress summaries."""

    def __init__(self, settings: StorageSettings) -> None:
        self.settings = settings
        self.output_dir = Path(settings.output_dir).resolve()
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Per-channel rolling buffers
        self._buffers: dict[str, RollingBuffer] = defaultdict(
            lambda: RollingBuffer(settings.max_history_messages)
        )

        # Time-series of summaries
        self._summaries: list[dict[str, Any]] = []
        self._lock = Lock()

        logger.info("MessageStore initialised at %s", self.output_dir)

    def store_messages(self, channel: str, messages: list[dict[str, Any]]) -> None:
        """Store a batch of messages for *channel*."""
        now = datetime.now(timezone.utc)
        enriched = []
        for msg in messages:
            if "timestamp" not in msg:
                msg["timestamp"] = now.isoformat()
            if "recorded_at" not in msg:
                msg["recorded_at"] = now.isoformat()
            msg["_channel"] = channel
            enriched.append(msg)

        self._buffers[channel].extend(enriched)

        if self.settings.save_raw_messages:
            self._append_to_jsonl(channel, enriched)

        logger.debug("Stored %d messages for channel '%s'", len(enriched), channel)

    def get_messages(
        self,
        channel: str | None = None,
        window_seconds: float | None = None,
    ) -> list[dict[str, Any]]:
        """Retrieve messages, optionally filtered by channel and time window."""
        channels = [channel] if channel else list(self._buffers.keys())
        result: list[dict[str, Any]] = []

        cutoff = None
        if window_seconds is not None:
            cutoff = datetime.now(timezone.utc).timestamp() - window_seconds

        for ch in channels:
            buf = self._buffers.get(ch)
            if buf is None:
                continue
            if cutoff is not None:
                result.extend(buf.get_since(cutoff))
            else:
                result.extend(buf.get_all())

        result.sort(key=lambda m: m.get("timestamp", ""))
        return result

    def store_summary(self, summary: dict[str, Any]) -> None:
        """Store a stress analysis summary."""
        if "generated_at" not in summary:
            summary["generated_at"] = datetime.now(timezone.utc).isoformat()

        with self._lock:
            self._summaries.append(summary)

        if self.settings.save_summaries:
            self._write_summary_file()

        logger.info("Stored stress summary (level=%s)", summary.get("overall_stress_level", "?"))

    def get_latest_summary(self) -> dict[str, Any] | None:
        """Return the most recent summary."""
        with self._lock:
            if self._summaries:
                return self._summaries[-1]
            return None

    def get_all_summaries(self) -> list[dict[str, Any]]:
        """Return all stored summaries."""
        with self._lock:
            return list(self._summaries)

    def clear(self) -> None:
        """Clear all in-memory data."""
        self._buffers.clear()
        with self._lock:
            self._summaries.clear()
        logger.info("MessageStore cleared")

    # ------------------------------------------------------------------
    # File persistence
    # ------------------------------------------------------------------

    def _append_to_jsonl(self, channel: str, messages: list[dict[str, Any]]) -> None:
        """Append messages to a channel-specific JSONL file."""
        log_path = self.output_dir / f"{channel}_{self.settings.raw_log_file}"
        try:
            with open(log_path, "a") as f:
                for msg in messages:
                    f.write(json.dumps(msg, default=str) + "\n")
        except OSError as e:
            logger.error("Failed to write JSONL for %s: %s", channel, e)

    def _write_summary_file(self) -> None:
        """Write all summaries to the summary file (atomically via rename)."""
        summary_path = self.output_dir / self.settings.summary_file
        tmp_path = summary_path.with_suffix(".tmp")
        try:
            with open(tmp_path, "w") as f:
                json.dump(
                    {"summaries": self._summaries, "count": len(self._summaries)},
                    f,
                    indent=2,
                    default=str,
                )
            tmp_path.rename(summary_path)
        except OSError as e:
            logger.error("Failed to write summary file: %s", e)

    def message_counts_by_channel(self, window_seconds: float) -> dict[str, int]:
        """Return message counts per channel within a time window."""
        cutoff = datetime.now(timezone.utc).timestamp() - window_seconds
        counts: dict[str, int] = {}
        for ch, buf in self._buffers.items():
            count = len(buf.get_since(cutoff))
            if count > 0:
                counts[ch] = count
        return counts