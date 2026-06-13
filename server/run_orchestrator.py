#!/usr/bin/env python3
"""
NeuroSync Orchestrator Runner

Starts the infinite polling loop that fetches messages from Discord + Email
every 15 seconds and performs LLM stress analysis.

Uses the openclaw CLI for all operations (channel polling + agent inference).

Usage:
    python run_orchestrator.py
    python run_orchestrator.py --config orchestrator.yaml
    python run_orchestrator.py --interval 30 --debug

Requirements:
    - openclaw CLI installed and configured
    - Gateway running (openclaw gateway run --force)
    - Channels configured (openclaw channels add --channel discord --token ...)
"""

from __future__ import annotations

import argparse
import asyncio
import logging
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from orchestrator import Orchestrator
from orchestrator.config import OrchestratorConfig


def _ensure_gateway() -> bool:
    """Check if the gateway is reachable; start it if not."""
    try:
        result = subprocess.run(
            ["openclaw", "gateway", "probe"],
            capture_output=True, text=True, timeout=10,
        )
        if "Reachable: yes" in result.stdout:
            return True
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Try to start it
    print("Gateway not reachable. Attempting to start...")
    try:
        env = os.environ.copy()
        # Use token from config or default
        env.setdefault("OPENCLAW_GATEWAY_TOKEN", "test-token-123")
        proc = subprocess.Popen(
            ["openclaw", "gateway", "run", "--force"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )
        print(f"Gateway process started (PID {proc.pid}). Waiting 6s for readiness...")
        time.sleep(6)
        return True
    except FileNotFoundError:
        print("ERROR: openclaw CLI not found. Install it first.")
        return False


def _show_channels() -> None:
    """Display configured channels."""
    try:
        result = subprocess.run(
            ["openclaw", "channels", "list"],
            capture_output=True, text=True, timeout=10,
        )
        if result.stdout:
            print("Configured channels:")
            for line in result.stdout.strip().split("\n"):
                if ":" in line:
                    name, status = line.split(":", 1)
                    print(f"  {name.strip()}:{status}")
    except Exception as e:
        print(f"  (could not list channels: {e})")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="NeuroSync Orchestrator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                          # Run with defaults (poll every 15s)
  %(prog)s --config config.yaml     # Use custom config
  %(prog)s --interval 30 --debug    # Poll every 30s with debug logs
  %(prog)s --no-gateway             # Assume gateway is already running
        """,
    )
    parser.add_argument("--config", "-c", default=None, help="Config file path")
    parser.add_argument("--interval", "-i", type=float, default=None, help="Poll interval (s)")
    parser.add_argument("--debug", "-d", action="store_true", help="Debug logging")
    parser.add_argument("--no-gateway", action="store_true", help="Skip gateway startup check")
    parser.add_argument("--version", "-v", action="store_true", help="Show version")

    args = parser.parse_args()

    if args.version:
        from orchestrator import __version__
        print(f"NeuroSync Orchestrator v{__version__}")
        sys.exit(0)

    # Logging
    level = logging.DEBUG if args.debug else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s.%(msecs)03d [%(levelname)-5s] %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )
    logging.getLogger("openclaw_sdk").setLevel(logging.WARNING)

    # Gateway
    if not args.no_gateway:
        if not _ensure_gateway():
            print("FATAL: Could not start or connect to OpenClaw gateway.")
            sys.exit(1)
        print("✓ Gateway is reachable.")
    else:
        print("  (gateway check skipped via --no-gateway)")

    # Show channel status
    _show_channels()

    # Load config
    config = OrchestratorConfig.from_env()
    if args.config:
        from orchestrator.config import load_config
        config = load_config(args.config)

    if args.interval is not None:
        config.global_poll_interval = args.interval
    if args.debug:
        config.debug = True

    print("═" * 60)
    print("  NeuroSync Orchestrator — OpenClaw Stress Analyser")
    print("═" * 60)
    print(f"  Poll interval : {config.global_poll_interval}s")
    print(f"  Discord       : {'enabled' if config.discord.enabled else 'disabled'}")
    print(f"  Email (Gmail) : {'enabled' if config.email.enabled else 'disabled'}")
    print(f"  LLM model     : {config.llm.model}")
    print(f"  Fallback AI   : {'enabled (keyword engine)' if config.llm.enable_crisis_detection else 'disabled'}")
    print(f"  Output dir    : {config.storage.output_dir}")
    print(f"  Data files    : {config.storage.summary_file}, {config.storage.raw_log_file}")
    print("═" * 60)
    print("  Starting orchestration loop... Press Ctrl+C to stop.")
    print()

    try:
        orchestrator = Orchestrator(config)
        asyncio.run(orchestrator.start())
    except KeyboardInterrupt:
        print("\n\nShutdown by user.")
    except Exception as e:
        print(f"\nFATAL: {e}")
        if args.debug:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()