"""Entry-point for running the orchestrator directly: python -m server.orchestrator"""

from __future__ import annotations

import argparse
import asyncio
import logging
import sys

from .config import load_config
from .orchestrator import Orchestrator


def _setup_logging(debug: bool) -> None:
    """Configure structured logging."""
    level = logging.DEBUG if debug else logging.INFO
    fmt = (
        "%(asctime)s.%(msecs)03d [%(levelname)-5s] %(name)s: %(message)s"
    )
    logging.basicConfig(
        level=level,
        format=fmt,
        datefmt="%H:%M:%S",
        stream=sys.stdout,
    )
    # Quiet down noisy libs
    for lib in ("openclaw_sdk", "asyncio", "urllib3"):
        logging.getLogger(lib).setLevel(logging.WARNING)


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="NeuroSync Orchestrator — OpenClaw message stress analyser",
    )
    parser.add_argument(
        "--config", "-c",
        type=str,
        default=None,
        help="Path to config JSON/YAML file",
    )
    parser.add_argument(
        "--interval", "-i",
        type=float,
        default=None,
        help="Poll interval in seconds (default: 15)",
    )
    parser.add_argument(
        "--debug", "-d",
        action="store_true",
        default=False,
        help="Enable debug logging",
    )
    parser.add_argument(
        "--version", "-v",
        action="store_true",
        help="Show version and exit",
    )
    args = parser.parse_args()

    if args.version:
        from . import __version__
        print(f"NeuroSync Orchestrator v{__version__}")
        sys.exit(0)

    _setup_logging(args.debug)

    config = load_config(args.config)

    if args.interval is not None:
        config.global_poll_interval = args.interval

    orchestrator = Orchestrator(config)

    try:
        asyncio.run(orchestrator.start())
    except KeyboardInterrupt:
        print("\nShutdown requested.")


if __name__ == "__main__":
    main()