"""LLM-driven stress analysis engine for polled messages.

Supports two analysis modes:
1. LLM agent mode: Uses OpenClaw CLI agent execution (openclaw agent --message ...)
2. Fallback mode: Keyword-based heuristic analysis when LLM is unavailable
"""

from __future__ import annotations

import asyncio
import json
import logging
import shlex
from datetime import datetime, timezone
from typing import Any

from .config import LLMSettings

logger = logging.getLogger("neurosync.analyser")


class StressAnalyser:
    """Analyses batches of messages for stress patterns, urgency, and trends.

    Uses the OpenClaw CLI agent to run LLM-based analysis when available,
    with a keyword-based fallback for offline operation.
    """

    def __init__(
        self,
        settings: LLMSettings,
    ) -> None:
        self._settings = settings
        self._history: list[dict[str, Any]] = []

    async def analyse(
        self,
        messages: list[dict[str, Any]],
        channel_name: str,
        window_seconds: float,
    ) -> dict[str, Any]:
        """Run stress analysis on a batch of messages.

        Args:
            messages: Normalised message dicts.
            channel_name: Source channel identifier.
            window_seconds: The time window these messages cover.

        Returns:
            A structured stress analysis result dict.
        """
        if not messages:
            return self._empty_result(channel_name, window_seconds)

        # Compute metadata
        message_count = len(messages)
        senders = list({
            m.get("sender", "unknown") for m in messages if m.get("sender")
        })
        unique_senders = len(senders)
        message_rate = round(
            message_count / (window_seconds / 60), 2
        ) if window_seconds > 0 else 0.0

        # Build a condensed text representation of messages
        message_texts = "\n".join(
            f"[{m.get('sender', '?')}] {m.get('text', '')[:300]}"
            for i, m in enumerate(messages)
            if m.get("text")
        )[:8000]  # Truncate to avoid exceeding token limits

        time_window_str = f"last {int(window_seconds)} seconds"
        if window_seconds >= 3600:
            time_window_str = f"last {round(window_seconds/3600, 1)} hours"
        elif window_seconds >= 60:
            time_window_str = f"last {int(window_seconds/60)} minutes"

        prompt = self._settings.analysis_prompt_template.format(
            channel_name=channel_name,
            time_window=time_window_str,
            message_count=message_count,
            unique_senders=unique_senders,
            message_rate=message_rate,
            message_texts=message_texts,
        )

        # Run analysis
        analysis_raw = await self._run_llm_analysis(prompt)

        # Structure the result
        result = self._parse_analysis(
            analysis_raw,
            channel_name,
            message_count,
            unique_senders,
            message_rate,
            time_window_str,
            messages,
        )

        # Update rolling history
        self._history.extend(messages)
        max_history = 500
        if len(self._history) > max_history:
            self._history = self._history[-max_history:]

        return result

    async def _run_llm_analysis(self, prompt: str) -> str:
        """Execute the LLM analysis via the OpenClaw CLI agent."""
        raw = await self._run_cli_analysis(prompt)
        if raw:
            return raw
        logger.info("LLM analysis unavailable — using keyword fallback")
        return self._fallback_analysis(prompt)

    async def _run_cli_analysis(self, prompt: str) -> str | None:
        """Run analysis via openclaw agent command."""
        try:
            # Escape the prompt for shell safety
            proc = await asyncio.create_subprocess_exec(
                "openclaw", "agent",
                "--agent", "main",
                "--message", prompt,
                "--json",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                proc.communicate(), timeout=30,
            )

            if proc.returncode != 0:
                err = stderr.decode().strip()
                logger.warning("Agent CLI error (rc=%d): %s", proc.returncode, err[:200])
                return None

            raw = stdout.decode().strip()
            if not raw:
                return None

            # Try to parse JSON response
            try:
                data = json.loads(raw)
                # Extract text content from various response formats
                if isinstance(data, dict):
                    content = (data.get("content") or data.get("text")
                               or data.get("response") or data.get("result"))
                    if content:
                        return str(content)
                    # If it's a structured result, pretty-print
                    return json.dumps(data, indent=2)
                elif isinstance(data, str):
                    return data
            except json.JSONDecodeError:
                pass

            return raw

        except asyncio.TimeoutError:
            logger.warning("Agent CLI timed out after 30s")
            return None
        except FileNotFoundError:
            logger.warning("openclaw CLI not found — cannot run LLM analysis")
            return None
        except Exception as e:
            logger.debug("Agent CLI error: %s", e)
            return None

    def _fallback_analysis(self, prompt: str) -> str:
        """Basic keyword-based analysis when the LLM agent is unavailable."""
        import re

        text_lower = prompt.lower()

        # Volume check
        msg_match = re.search(r"Total messages: (\d+)", prompt)
        msg_count = int(msg_match.group(1)) if msg_match else 0

        # Keyword-based stress detection
        crisis_keywords = [
            "urgent", "critical", "emergency", "asap", "help",
            "blocked", "broken", "failure", "crash", "fire",
            "security", "breach", "attack", "downtime",
            "production down", "sev1", "p0", "p1", "outage",
            "data loss", "compromised", "vulnerability",
        ]
        stress_keywords = [
            "stress", "overwhelmed", "pressure", "deadline",
            "struggle", "difficult", "hard", "tight",
            "concern", "worried", "issue", "problem",
            "overworked", "burnout", "exhausted",
        ]
        positive_keywords = [
            "great", "awesome", "good", "done", "completed",
            "thanks", "thank you", "perfect", "success",
            "excellent", "amazing", "fantastic", "solved",
        ]

        crisis_count = sum(1 for kw in crisis_keywords if kw in text_lower)
        stress_count = sum(1 for kw in stress_keywords if kw in text_lower)
        positive_count = sum(1 for kw in positive_keywords if kw in text_lower)

        # Determine stress level
        if crisis_count >= 2 or (msg_count > 15 and crisis_count >= 1):
            level = "critical"
        elif crisis_count >= 1 or (msg_count > 10 and stress_count >= 3):
            level = "high"
        elif stress_count >= 3 or (msg_count > 20):
            level = "moderate"
        elif stress_count >= 1 and positive_count <= stress_count:
            level = "low"
        else:
            level = "none"

        # Volume trend
        if msg_count > 15:
            volume = "rising"
        elif msg_count > 5:
            volume = "stable"
        else:
            volume = "stable"

        # Sentiment
        if positive_count > stress_count + crisis_count:
            sentiment = "positive"
        elif crisis_count > positive_count:
            sentiment = "negative"
        else:
            sentiment = "neutral"

        crisis = "yes" if crisis_count >= 1 else "no"

        # Build themes
        detected_themes = []
        if any(kw in text_lower for kw in ["deploy", "release", "ci/cd", "build"]):
            detected_themes.append("deployment")
        if any(kw in text_lower for kw in ["bug", "error", "fail", "crash"]):
            detected_themes.append("bugs/errors")
        if any(kw in text_lower for kw in ["customer", "user", "client", "support"]):
            detected_themes.append("customer/support")
        if any(kw in text_lower for kw in ["secur", "breach", "vulnerab", "attack"]):
            detected_themes.append("security")
        if any(kw in text_lower for kw in ["meeting", "schedule", "deadline"]):
            detected_themes.append("scheduling")

        theme_str = ", ".join(detected_themes) if detected_themes else "general communication"

        return (
            f"OVERALL_STRESS_LEVEL: {level}\n"
            f"URGENT_ITEMS: {crisis_count} potential urgent message(s) detected\n"
            f"VOLUME_TREND: {volume}\n"
            f"TOP_THEMES: {theme_str}\n"
            f"SENTIMENT: {sentiment}\n"
            f"CRISIS_FLAG: {crisis}\n"
            f"SUMMARY: {msg_count} messages from this poll cycle. "
            f"Stress indicators: {stress_count}. "
            f"Crisis indicators: {crisis_count}. "
            f"Overall communication tone is {sentiment}."
        )

    def _parse_analysis(
        self,
        raw: str,
        channel_name: str,
        message_count: int,
        unique_senders: int,
        message_rate: float,
        time_window: str,
        messages: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Parse the LLM's analysis output into a structured result."""
        import re

        def _extract(label: str) -> str:
            pattern = rf"{label}:\s*(.+?)(?:\n|$)"
            m = re.search(pattern, raw, re.IGNORECASE)
            return m.group(1).strip() if m else "unknown"

        overall_stress = _extract("OVERALL_STRESS_LEVEL")
        urgent_raw = _extract("URGENT_ITEMS")
        volume_trend = _extract("VOLUME_TREND")
        top_themes = _extract("TOP_THEMES")
        sentiment = _extract("SENTIMENT")
        crisis_flag = _extract("CRISIS_FLAG")
        summary = _extract("SUMMARY")

        # Urgent items detection
        urgent_items = [msg for msg in messages if self._is_urgent(msg)]

        result: dict[str, Any] = {
            "overall_stress_level": overall_stress,
            "urgent_items": urgent_items[:10],
            "urgent_count": len(urgent_items),
            "urgent_summary": urgent_raw[:500] if urgent_raw != "unknown" else "",
            "volume_trend": volume_trend,
            "top_themes": [
                t.strip() for t in top_themes.split(",") if t.strip()
            ] if top_themes != "unknown" else [],
            "sentiment": sentiment,
            "crisis_flag": crisis_flag.lower() == "yes",
            "summary": summary[:500] if summary != "unknown" else "",
            "metrics": {
                "message_count": message_count,
                "unique_senders": unique_senders,
                "message_rate_per_min": message_rate,
                "time_window": time_window,
            },
            "channel": channel_name,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }
        return result

    def _is_urgent(self, message: dict[str, Any]) -> bool:
        """Heuristic flag: does this message look urgent?"""
        text = (message.get("text") or "").lower()
        urgent_signals = [
            "urgent", "asap", "critical", "emergency", "immediately",
            "blocking", "blocked", "down", "broken", "crash",
            "help", "fire", "security", "breach", "p0", "p1",
            "deadline", "overdue", "escalate", "sos",
            "production", "outage",
        ]
        return any(signal in text for signal in urgent_signals)

    def _empty_result(
        self, channel_name: str, window_seconds: float,
    ) -> dict[str, Any]:
        """Return a neutral result when there are no messages."""
        return {
            "overall_stress_level": "none",
            "urgent_items": [],
            "urgent_count": 0,
            "urgent_summary": "",
            "volume_trend": "stable",
            "top_themes": [],
            "sentiment": "neutral",
            "crisis_flag": False,
            "summary": f"No messages in the last {int(window_seconds)}s for {channel_name}.",
            "metrics": {
                "message_count": 0,
                "unique_senders": 0,
                "message_rate_per_min": 0.0,
                "time_window": f"{int(window_seconds)} seconds",
            },
            "channel": channel_name,
            "generated_at": datetime.now(timezone.utc).isoformat(),
        }