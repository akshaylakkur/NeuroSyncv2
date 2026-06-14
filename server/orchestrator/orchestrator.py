"""Main NeuroSync orchestrator — coordinating 15-second poll+analyse-summarise loop."""

from __future__ import annotations

import asyncio
import json
import logging
import signal
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .analyser import StressAnalyser
from .config import OrchestratorConfig
from .poller import BasePoller, create_poller
from .storage import MessageStore

logger = logging.getLogger("neurosync.orchestrator")


class Orchestrator:
    """Top-level orchestrator that runs the infinite poll-analyse-summarise loop.

    Architecture:
        ┌─────────────────────────────────────────────────┐
        │  Orchestrator  (every 15s)                      │
        │  ┌──────────┐   ┌──────────┐   ┌────────────┐  │
        │  │ Discord  │   │  Gmail   │   │   Future    │  │
        │  │ Poller   │   │  Poller  │   │  Channels   │  │
        │  └────┬─────┘   └────┬─────┘   └─────┬──────┘  │
        │       └──────┬───────┘               │          │
        │              ▼                       │          │
        │      ┌───────────────┐               │          │
        │      │  MessageStore  │◄──────────────┘          │
        │      └───────┬───────┘                           │
        │              ▼                                   │
        │      ┌───────────────┐                           │
        │      │ StressAnalyser│  (LLM analysis)           │
        │      └───────┬───────┘                           │
        │              ▼                                   │
        │      ┌───────────────┐                           │
        │      │   Summary     │  → stdout / file / API    │
        │      └───────────────┘                           │
        └─────────────────────────────────────────────────┘
    """

    def __init__(self, config: OrchestratorConfig | None = None) -> None:
        self.config = config or OrchestratorConfig.from_env()
        self._pollers: list[BasePoller] = []
        self._analyser: StressAnalyser | None = None
        self._store: MessageStore | None = None
        self._running = False
        self._loop_count = 0
        self._shutdown_event = asyncio.Event()
        self._aggregated_summaries: list[dict[str, Any]] = []

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    async def start(self) -> None:
        """Start the orchestrator: initialise components, run loop."""
        self._running = True
        logger.info("NeuroSync Orchestrator v%s starting...", "1.0.0")

        # Initialise storage
        self._store = MessageStore(self.config.storage)

        # Initialise analyser (LLM via subprocess/fallback)
        self._analyser = StressAnalyser(self.config.llm)

        # Create pollers for enabled channels (skip if already injected, e.g. by simulation)
        if not self._pollers:
            self._pollers = self._init_pollers()

        if not self._pollers:
            logger.warning(
                "No pollers initialised. No channels are enabled. "
                "Set NEUROSYNC_DISCORD_ENABLED=true or NEUROSYNC_EMAIL_ENABLED=true"
            )

        logger.info(
            "Orchestrator ready — polling %d channel(s) every %.1fs",
            len(self._pollers),
            self.config.global_poll_interval,
        )

        # Install signal handlers for graceful shutdown
        self._install_signal_handlers()

        # Main loop
        try:
            await self._run_loop()
        except asyncio.CancelledError:
            logger.info("Orchestrator loop cancelled")
        except Exception as e:
            logger.exception("Fatal error in orchestrator loop: %s", e)
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Gracefully stop the orchestrator and clean up."""
        self._running = False
        self._shutdown_event.set()
        logger.info("NeuroSync Orchestrator stopped")

    # ------------------------------------------------------------------
    # Status / query methods
    # ------------------------------------------------------------------

    async def get_latest_analysis(self) -> dict[str, Any] | None:
        """Get the most recent aggregated analysis result."""
        if self._aggregated_summaries:
            return self._aggregated_summaries[-1]
        if self._store:
            return self._store.get_latest_summary()
        return None

    async def get_all_analyses(self) -> list[dict[str, Any]]:
        """Get all stored analyses."""
        if self._store:
            return self._store.get_all_summaries()
        return list(self._aggregated_summaries)

    # ------------------------------------------------------------------
    # Internal: Poller initialisation
    # ------------------------------------------------------------------

    def _init_pollers(self) -> list[BasePoller]:
        """Initialise pollers for all enabled channels."""
        pollers: list[BasePoller] = []

        # Discord
        if self.config.discord.enabled:
            try:
                poller = create_poller("discord", self.config.discord)
                pollers.append(poller)
                logger.info("Discord poller initialised")
            except Exception as e:
                logger.error("Failed to initialise Discord poller: %s", e)

        # Gmail / Email
        if self.config.email.enabled:
            try:
                poller = create_poller("gmail", self.config.email)
                pollers.append(poller)
                logger.info("Gmail poller initialised")
            except Exception as e:
                logger.error("Failed to initialise Gmail poller: %s", e)

        # Simulated (HTTP) pollers — for demo/development
        if self.config.simulated.enabled:
            for ch_name in self.config.simulated.channel_names:
                try:
                    poller = create_poller(ch_name, self.config.simulated)
                    pollers.append(poller)
                    logger.info(
                        "Simulated HTTP poller '%s' initialised (→ %s)",
                        ch_name, self.config.simulated.simulator_url,
                    )
                except Exception as e:
                    logger.error(
                        "Failed to initialise simulated poller '%s': %s", ch_name, e,
                    )

        return pollers

    # ------------------------------------------------------------------
    # Internal: Main loop
    # ------------------------------------------------------------------

    async def _run_loop(self) -> None:
        """Run the infinite poll-analyse-summarise loop."""
        while self._running:
            self._loop_count += 1
            loop_start = time.monotonic()

            try:
                await self._poll_and_analyse()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.exception("Error in poll/analyse cycle: %s", e)

            elapsed = time.monotonic() - loop_start
            sleep_time = max(0, self.config.global_poll_interval - elapsed)

            logger.debug(
                "Cycle %d complete in %.2fs — sleeping %.1fs",
                self._loop_count, elapsed, sleep_time,
            )

            try:
                await asyncio.wait_for(
                    self._shutdown_event.wait(),
                    timeout=sleep_time,
                )
                break  # Shutdown requested
            except asyncio.TimeoutError:
                continue  # Normal: timeout means keep going

    async def _poll_and_analyse(self) -> None:
        """One full poll + analyse + summarise cycle."""
        if not self._pollers or not self._store or not self._analyser:
            logger.warning("Components not ready — skipping cycle")
            return

        all_messages: list[dict[str, Any]] = []
        channel_message_map: dict[str, list[dict[str, Any]]] = {}

        # ---- Phase 1: Poll all channels concurrently ----
        poll_tasks = {
            poller.channel_name: poller.poll()
            for poller in self._pollers
        }
        poll_results = await asyncio.gather(
            *poll_tasks.values(),
            return_exceptions=True,
        )

        for (ch_name, _), result in zip(poll_tasks.items(), poll_results):
            if isinstance(result, Exception):
                logger.error("Poll failed for '%s': %s", ch_name, result)
                continue
            messages = result
            if messages:
                channel_message_map[ch_name] = messages
                all_messages.extend(messages)
                self._store.store_messages(ch_name, messages)
                logger.info(
                    "Polled %d message(s) from '%s'",
                    len(messages), ch_name,
                )

        if not all_messages:
            logger.debug("No new messages in this cycle")
            channel_summaries = []
            for poller in self._pollers:
                empty_result = self._analyser._empty_result(
                    poller.channel_name, self.config.global_poll_interval,
                )
                self._store.store_summary(empty_result)
                channel_summaries.append(empty_result)

            # Always create an aggregated summary so the dashboard
            # reflects the current (empty) state, not stale old data.
            aggregated = self._aggregate_analyses(channel_summaries, [])
            self._aggregated_summaries.append(aggregated)
            self._store.store_summary(aggregated)
            self._emit_summary(aggregated)
            return

        # ---- Phase 2: Per-channel LLM stress analysis ----
        analysis_tasks = []
        for ch_name, msgs in channel_message_map.items():
            analysis_tasks.append(
                self._analyser.analyse(
                    msgs,
                    ch_name,
                    self.config.global_poll_interval,
                )
            )

        analysis_results = await asyncio.gather(
            *analysis_tasks, return_exceptions=True,
        )

        per_channel_summaries: list[dict[str, Any]] = []
        for result in analysis_results:
            if isinstance(result, Exception):
                logger.error("Analysis failed: %s", result)
                continue
            per_channel_summaries.append(result)
            self._store.store_summary(result)

        # ---- Phase 3: Cross-channel aggregation ----
        aggregated = self._aggregate_analyses(
            per_channel_summaries,
            all_messages,
        )
        self._aggregated_summaries.append(aggregated)
        self._store.store_summary(aggregated)

        # ---- Phase 4: Emit output ----
        self._emit_summary(aggregated)

    # ------------------------------------------------------------------
    # Internal: Aggregation
    # ------------------------------------------------------------------

    def _aggregate_analyses(
        self,
        channel_results: list[dict[str, Any]],
        all_messages: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Combine per-channel analyses into a cross-channel aggregated summary."""
        total_messages = len(all_messages)
        total_senders = len(
            {m.get("sender", "") for m in all_messages if m.get("sender")}
        )

        stress_levels = [
            r.get("overall_stress_level", "none") for r in channel_results
        ]
        level_rank = {"none": 0, "low": 1, "moderate": 2, "high": 3, "critical": 4}
        worst_level = max(stress_levels, key=lambda l: level_rank.get(l, 0))

        any_crisis = any(r.get("crisis_flag", False) for r in channel_results)
        total_urgent = sum(r.get("urgent_count", 0) for r in channel_results)

        all_themes: set[str] = set()
        for r in channel_results:
            for theme in r.get("top_themes", []):
                if theme and theme != "Auto-detected keywords":
                    all_themes.add(theme)

        channel_breakdown: dict[str, dict[str, int]] = {}
        channel_names = {m.get("channel", "unknown") for m in all_messages}
        for ch in sorted(channel_names):
            ch_msgs = [m for m in all_messages if m.get("channel") == ch]
            channel_breakdown[ch] = {
                "count": len(ch_msgs),
                "unique_senders": len(
                    {m.get("sender", "") for m in ch_msgs}
                ),
            }

        now = datetime.now(timezone.utc)
        aggregated: dict[str, Any] = {
            "type": "aggregated_summary",
            "timestamp": now.isoformat(),
            "total_messages": total_messages,
            "total_unique_senders": total_senders,
            "overall_stress_level": worst_level,
            "crisis_flag": any_crisis,
            "total_urgent_items": total_urgent,
            "top_themes_across_channels": sorted(all_themes) if all_themes else [],
            "channel_breakdown": channel_breakdown,
            "active_channels": sorted(channel_names),
            "cycle_number": self._loop_count,
        }
        return aggregated

    # ------------------------------------------------------------------
    # Internal: Output
    # ------------------------------------------------------------------

    def _emit_summary(self, aggregated: dict[str, Any]) -> None:
        """Emit the aggregated summary to stdout in a readable format."""
        level = aggregated.get("overall_stress_level", "none")
        crisis = "🚨 CRISIS" if aggregated.get("crisis_flag") else "✓ OK"
        urgent = aggregated.get("total_urgent_items", 0)
        total = aggregated.get("total_messages", 0)
        channels = aggregated.get("active_channels", [])
        ch_breakdown = aggregated.get("channel_breakdown", {})

        print("─" * 60)
        print(
            f"[{aggregated.get('timestamp', '?')}] "
            f"Cycle #{self._loop_count} | "
            f"Stress: {level.upper():>8} {crisis} | "
            f"Msgs: {total:>3} | "
            f"Urgent: {urgent:>2} | "
            f"Channels: {', '.join(channels)}"
        )
        for ch, stats in ch_breakdown.items():
            print(f"  ├─ {ch}: {stats['count']} msgs, {stats['unique_senders']} senders")
        if aggregated.get("top_themes_across_channels"):
            themes = aggregated["top_themes_across_channels"][:5]
            print(f"  └─ Themes: {', '.join(themes)}")
        sys.stdout.flush()

        self._write_summary_to_file(aggregated)

    def _write_summary_to_file(self, aggregated: dict[str, Any]) -> None:
        """Write the latest aggregated summary to a JSON file."""
        if not self.config.storage.save_summaries:
            return
        try:
            output_path = Path(self.config.storage.output_dir) / "latest_summary.json"
            with open(output_path, "w") as f:
                json.dump(aggregated, f, indent=2, default=str)
        except OSError as e:
            logger.error("Failed to write latest summary: %s", e)

    # ------------------------------------------------------------------
    # Internal: Signal handling
    # ------------------------------------------------------------------

    def _install_signal_handlers(self) -> None:
        """Install SIGINT/SIGTERM handlers for graceful shutdown."""
        loop = asyncio.get_event_loop()

        try:
            loop.add_signal_handler(
                signal.SIGINT,
                lambda: asyncio.ensure_future(self._handle_signal("SIGINT")),
            )
            loop.add_signal_handler(
                signal.SIGTERM,
                lambda: asyncio.ensure_future(self._handle_signal("SIGTERM")),
            )
        except NotImplementedError:
            logger.debug("Signal handlers not supported on this platform")

    async def _handle_signal(self, signame: str) -> None:
        """Handle shutdown signals."""
        logger.info("Received %s — shutting down gracefully...", signame)
        self._running = False
        self._shutdown_event.set()