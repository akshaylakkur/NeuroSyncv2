"""
NeuroSync Bridge Server — Extended social sentiment API for iOS app consumption.

Endpoints:
  GET  /social/dashboard        — Full social sentiment dashboard
  GET  /social/messages         — Recent messages with sentiment
  GET  /social/urgent           — Urgent/crisis messages
  POST /social/health-correlation — Receive health stress from iOS app
  POST /social/create-reminder  — Queue a reminder from social stress
  GET  /social/pending-reminders — Poll pending reminders (iOS app)
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

logger = logging.getLogger("neurosync.social")

# ======================================================================
# Pydantic Models
# ======================================================================

class SocialMessageOut(BaseModel):
    id: str
    text: str
    sender: str
    channel: str
    timestamp: str
    is_urgent: bool
    is_crisis: bool
    sentiment_label: str = "neutral"

class SentimentSummaryOut(BaseModel):
    channel: str
    message_count: int
    unique_senders: int
    overall_stress_level: str
    sentiment: str
    crisis_flag: bool
    urgent_count: int
    top_themes: list[str]
    summary: str
    generated_at: str

class SocialDashboardOut(BaseModel):
    last_updated: str
    total_messages_today: int
    total_urgent: int
    crisis_active: bool
    overall_mood: str
    combined_stress_level: str
    channels: list[SentimentSummaryOut]
    recent_messages: list[SocialMessageOut]
    health_social_correlation: str | None = None


# ======================================================================
# Global state (shared across endpoints)
# ======================================================================

_health_stress_data: dict[str, Any] = {}


def register_social_routes(app: FastAPI, get_orchestrator_fn):
    """Register all social sentiment routes on the FastAPI app."""

    # ------------------------------------------------------------------
    # POST /social/health-correlation
    # ------------------------------------------------------------------
    @app.post("/social/health-correlation")
    async def social_health_correlation(payload: dict[str, Any]):
        """Receive health stress data from the iOS app for cross-correlation."""
        global _health_stress_data
        _health_stress_data = {
            "stress_level": payload.get("stress_level", "unknown"),
            "confidence": payload.get("confidence", 0.0),
            "timestamp": payload.get("timestamp", datetime.now(timezone.utc).isoformat()),
        }
        orch = get_orchestrator_fn()
        if orch:
            orch._latest_health_stress = payload.get("stress_level", "unknown")
        return {"status": "ok", "received": _health_stress_data}

    # ------------------------------------------------------------------
    # POST /social/create-reminder
    # ------------------------------------------------------------------
    @app.post("/social/create-reminder")
    async def social_create_reminder(payload: dict[str, Any]):
        """Queue a reminder based on social stress for the iOS app to pick up."""
        stress_level = payload.get("stress_level", "unknown")
        reason = payload.get("reason", "Social sentiment indicates elevated stress")
        source = payload.get("source", "social_sentiment")

        reminder_data = {
            "title": "🧠 NeuroSync: Social Stress Alert",
            "notes": reason[:500],
            "stress_level": stress_level,
            "source": source,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }

        orch = get_orchestrator_fn()
        if orch:
            if not hasattr(orch, '_pending_reminders'):
                orch._pending_reminders = []
            orch._pending_reminders.append(reminder_data)

        return {"success": True, "reminder": reminder_data}

    # ------------------------------------------------------------------
    # GET /social/pending-reminders
    # ------------------------------------------------------------------
    @app.get("/social/pending-reminders")
    async def social_pending_reminders():
        """Get pending reminders for the iOS app to create locally via EventKit."""
        orch = get_orchestrator_fn()
        if not orch:
            return {"reminders": []}
        reminders = list(getattr(orch, '_pending_reminders', []))
        orch._pending_reminders = []  # Clear after serving
        return {"reminders": reminders}

    # ------------------------------------------------------------------
    # GET /social/dashboard
    # ------------------------------------------------------------------
    @app.get("/social/dashboard", response_model=SocialDashboardOut)
    async def social_dashboard():
        """Get the full social sentiment dashboard for the iOS app."""
        orch = get_orchestrator_fn()
        if not orch or not orch._store or not orch._analyser:
            raise HTTPException(status_code=503, detail="Orchestrator not ready")

        latest = await orch.get_latest_analysis() or {}
        all_msgs = orch._store.get_messages(
            window_seconds=orch.config.global_poll_interval * 8
        )

        # Group by channel
        from collections import defaultdict
        channel_map: dict[str, dict[str, Any]] = defaultdict(lambda: {
            "messages": [], "stress_entries": []
        })

        for msg in all_msgs:
            ch = msg.get("channel", "unknown")
            channel_map[ch]["messages"].append(msg)

        store_summaries = orch._store.get_all_summaries()
        for s in store_summaries:
            ch = s.get("channel")
            if ch and ch in channel_map:
                channel_map[ch]["stress_entries"].append(s)

        channels_out: list[SentimentSummaryOut] = []
        for ch_name, data in channel_map.items():
            msgs = data["messages"]
            entries = data["stress_entries"]

            latest_entry = entries[-1] if entries else latest
            stress = latest_entry.get("overall_stress_level", "none") if latest_entry else "none"
            sentiment = latest_entry.get("sentiment", "neutral") if latest_entry else "neutral"
            crisis = latest_entry.get("crisis_flag", False) if latest_entry else False
            themes = latest_entry.get("top_themes", []) if latest_entry else []
            summary_text = latest_entry.get("summary", "") if latest_entry else ""
            urgent = latest_entry.get("urgent_count", 0) if latest_entry else 0

            senders = set()
            for m in msgs:
                s = m.get("sender", "unknown")
                if s:
                    senders.add(s)

            channels_out.append(SentimentSummaryOut(
                channel=ch_name,
                message_count=len(msgs),
                unique_senders=len(senders),
                overall_stress_level=stress,
                sentiment=sentiment,
                crisis_flag=crisis,
                urgent_count=urgent,
                top_themes=themes if isinstance(themes, list) else [],
                summary=summary_text,
                generated_at=latest_entry.get("generated_at", datetime.now(timezone.utc).isoformat()) if latest_entry else "",
            ))

        # Recent messages (urgent first)
        urgent_msgs = [m for m in all_msgs if _is_msg_urgent(m)]
        non_urgent = [m for m in all_msgs if not _is_msg_urgent(m)]
        sorted_msgs = sorted(urgent_msgs, key=lambda m: m.get("timestamp", ""), reverse=True)
        sorted_msgs += sorted(non_urgent, key=lambda m: m.get("timestamp", ""), reverse=True)
        recent = sorted_msgs[:20]

        messages_out = []
        for m in recent:
            messages_out.append(SocialMessageOut(
                id=m.get("id", ""),
                text=m.get("text", "")[:500],
                sender=str(m.get("sender", "unknown")),
                channel=m.get("channel", "unknown"),
                timestamp=str(m.get("timestamp", "")),
                is_urgent=_is_msg_urgent(m),
                is_crisis=_is_crisis_msg(m),
                sentiment_label=_message_sentiment(m),
            ))

        combined = latest.get("overall_stress_level", "none")
        crisis = latest.get("crisis_flag", False)
        total_urgent = latest.get("total_urgent_items", 0)
        total_msgs = latest.get("total_messages", 0)

        # Health–social correlation
        correlation = None
        health_stress = getattr(orch, '_latest_health_stress', None)
        if health_stress and combined != "none":
            correlation = f"Health: {health_stress} / Social: {combined}"

        return SocialDashboardOut(
            last_updated=datetime.now(timezone.utc).isoformat(),
            total_messages_today=total_msgs,
            total_urgent=total_urgent,
            crisis_active=crisis,
            overall_mood=latest.get("sentiment", "neutral"),
            combined_stress_level=combined,
            channels=channels_out,
            recent_messages=messages_out,
            health_social_correlation=correlation,
        )

    # ------------------------------------------------------------------
    # GET /social/messages
    # ------------------------------------------------------------------
    @app.get("/social/messages", response_model=list[SocialMessageOut])
    async def social_messages(channel: str | None = None, limit: int = 50):
        """Get recent social messages with sentiment data."""
        orch = get_orchestrator_fn()
        if not orch or not orch._store:
            raise HTTPException(status_code=503, detail="Orchestrator not ready")

        all_msgs = orch._store.get_messages(
            channel=channel,
            window_seconds=orch.config.global_poll_interval * 8,
        )

        urgent_msgs = [m for m in all_msgs if _is_msg_urgent(m)]
        non_urgent = [m for m in all_msgs if not _is_msg_urgent(m)]
        sorted_msgs = sorted(urgent_msgs, key=lambda m: m.get("timestamp", ""), reverse=True)
        sorted_msgs += sorted(non_urgent, key=lambda m: m.get("timestamp", ""), reverse=True)
        sorted_msgs = sorted_msgs[:limit]

        return [
            SocialMessageOut(
                id=m.get("id", ""),
                text=m.get("text", "")[:500],
                sender=str(m.get("sender", "unknown")),
                channel=m.get("channel", "unknown"),
                timestamp=str(m.get("timestamp", "")),
                is_urgent=_is_msg_urgent(m),
                is_crisis=_is_crisis_msg(m),
                sentiment_label=_message_sentiment(m),
            )
            for m in sorted_msgs
        ]

    # ------------------------------------------------------------------
    # GET /social/urgent
    # ------------------------------------------------------------------
    @app.get("/social/urgent")
    async def social_urgent():
        """Get only urgent/crisis messages for alerting."""
        orch = get_orchestrator_fn()
        if not orch or not orch._store:
            raise HTTPException(status_code=503, detail="Orchestrator not ready")

        all_msgs = orch._store.get_messages(
            window_seconds=orch.config.global_poll_interval * 8,
        )
        urgent = [m for m in all_msgs if _is_msg_urgent(m) or _is_crisis_msg(m)]
        urgent.sort(key=lambda m: m.get("timestamp", ""), reverse=True)

        return {
            "count": len(urgent),
            "crisis_active": any(_is_crisis_msg(m) for m in urgent),
            "messages": [
                SocialMessageOut(
                    id=m.get("id", ""),
                    text=m.get("text", "")[:500],
                    sender=str(m.get("sender", "unknown")),
                    channel=m.get("channel", "unknown"),
                    timestamp=str(m.get("timestamp", "")),
                    is_urgent=True,
                    is_crisis=_is_crisis_msg(m),
                    sentiment_label=_message_sentiment(m),
                )
                for m in urgent[:20]
            ],
        }


# ======================================================================
# Helper functions
# ======================================================================

URGENT_SIGNALS = [
    "urgent", "asap", "critical", "emergency", "immediately",
    "blocking", "blocked", "down", "broken", "crash",
    "help", "fire", "security", "breach", "p0", "p1",
    "deadline", "overdue", "escalate", "sos", "production", "outage",
]

CRISIS_SIGNALS = [
    "production down", "security breach", "data loss", "compromised",
    "vulnerability", "attack", "emergency", "fire", "crash",
    "sev1", "p0", "outage",
]


def _is_msg_urgent(message: dict[str, Any]) -> bool:
    text = (message.get("text") or "").lower()
    return any(signal in text for signal in URGENT_SIGNALS)


def _is_crisis_msg(message: dict[str, Any]) -> bool:
    text = (message.get("text") or "").lower()
    return any(signal in text for signal in CRISIS_SIGNALS)


def _message_sentiment(message: dict[str, Any]) -> str:
    """Simple heuristic sentiment for a single message."""
    text = (message.get("text") or "").lower()
    positive = ["thanks", "great", "awesome", "good", "done", "completed", "perfect", "solved"]
    negative = ["urgent", "broken", "failed", "crash", "blocked", "issue", "problem", "down"]
    pos_count = sum(1 for w in positive if w in text)
    neg_count = sum(1 for w in negative if w in text)
    if pos_count > neg_count:
        return "positive"
    elif neg_count > pos_count:
        return "negative"
    return "neutral"