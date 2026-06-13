# NeuroSync Orchestrator — OpenClaw Message Stress Analyser

A sophisticated Python orchestrator that polls **Discord** and **Email (Gmail)** channels every **15 seconds** via the OpenClaw SDK, performs **LLM-driven stress analysis** on the messages, and produces a running summary.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    NeuroSync Orchestrator                       │
│                                                                 │
│  ┌────────────────┐    ┌────────────────┐    ┌───────────────┐  │
│  │  Discord       │    │  Gmail         │    │   Future      │  │
│  │  Poller        │    │  Poller        │    │   Channels    │  │
│  └───────┬────────┘    └───────┬────────┘    └───────┬───────┘  │
│          └──────────┬─────────┘          ┌───────────┘          │
│                     ▼                    ▼                      │
│          ┌──────────────────────────────────────┐               │
│          │          MessageStore                 │               │
│          │  (Rolling buffer + JSONL persistence) │               │
│          └──────────────────┬───────────────────┘               │
│                             ▼                                   │
│          ┌──────────────────────────────────────┐               │
│          │          StressAnalyser               │               │
│          │   (LLM agent / fallback keyword AI)   │               │
│          └──────────────────┬───────────────────┘               │
│                             ▼                                   │
│          ┌──────────────────────────────────────┐               │
│          │      Aggregated Summary              │               │
│          │  (stdout + JSON + REST API)          │               │
│          └──────────────────────────────────────┘               │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  OpenClaw Gateway (ws://127.0.0.1:18789)                  │   │
│  │  • Manages channel connections (Discord, Gmail)           │   │
│  │  • Routes LLM inference requests                          │   │
│  │  • WebSocket RPC for message.read, agents.execute         │   │
│  └──────────────────────────────────────────────────────────┘   │
│                  ▲                                              │
│                  │ WebSocket RPC                                 │
│          ┌───────┴────────┐                                     │
│          │  openclaw-sdk  │                                     │
│          │  (Python SDK)  │                                     │
│          └────────────────┘                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **Dual-channel polling**: Discord + Email (Gmail) every 15 seconds
- **LLM Stress Analysis**: Uses OpenClaw agents to run analysis on:
  - Overall stress level (none/low/moderate/high/critical)
  - Urgent item detection
  - Volume trend analysis (rising/stable/falling)
  - Topic classification & theme extraction
  - Sentiment analysis
  - Crisis/emergency flagging
- **Smart fallback**: Keyword-based analysis engine when LLM agent is unavailable
- **Rolling buffer**: Thread-safe message storage with configurable history
- **Persistence**: JSONL raw message logs + JSON summary files
- **Cross-channel aggregation**: Combines Discord + Email insights
- **Graceful shutdown**: Signal handling for SIGINT/SIGTERM
- **REST API**: FastAPI server exposing all analysis data
- **Configurable**: Environment variables, YAML/JSON config files
- **Exponential backoff**: Connection retry with smart delays

## Quick Start

### 1. Prerequisites

```bash
# Install OpenClaw CLI (already installed)
openclaw version

# Install Python dependencies
pip install openclaw-sdk fastapi uvicorn pyyaml
```

### 2. Start the Gateway

```bash
# Set up auth
openclaw config set gateway.auth.mode token
openclaw config set gateway.auth.token test-token-123

# Start gateway in background
export OPENCLAW_GATEWAY_TOKEN=test-token-123
openclaw gateway run --force &
```

### 3. Configure Channels

```bash
# Add Discord
openclaw channels add --channel discord --token YOUR_DISCORD_BOT_TOKEN

# Add Gmail (needs OAuth token)
openclaw channels add --channel gmail --token YOUR_GMAIL_OAUTH_TOKEN
```

### 4. Run the Orchestrator

```bash
cd server
python run_orchestrator.py
```

## Command Line Options

```bash
python run_orchestrator.py --help

Options:
  --config, -c PATH     Config file (YAML/JSON)
  --interval, -i SECS   Poll interval (default: 15)
  --debug, -d           Enable debug logging
  --no-gateway          Skip gateway startup check
  --version, -v         Show version
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NEUROSYNC_GW_URL` | `ws://127.0.0.1:18789` | Gateway WebSocket URL |
| `NEUROSYNC_GW_TOKEN` | `""` | Gateway auth token |
| `NEUROSYNC_GW_MODE` | `local` | Gateway mode |
| `NEUROSYNC_DISCORD_ENABLED` | `true` | Enable Discord polling |
| `NEUROSYNC_DISCORD_GUILD_ID` | `""` | Restrict to one guild |
| `NEUROSYNC_DISCORD_MAX_MSGS` | `50` | Max messages per poll |
| `NEUROSYNC_EMAIL_ENABLED` | `true` | Enable Gmail polling |
| `NEUROSYNC_EMAIL_QUERY` | `is:unread` | Gmail search query |
| `NEUROSYNC_EMAIL_MAX_RESULTS` | `20` | Max emails per poll |
| `NEUROSYNC_LLM_MODEL` | `openai/gpt-4o-mini` | LLM model for analysis |
| `NEUROSYNC_POLL_INTERVAL` | `15` | Poll interval (seconds) |
| `NEUROSYNC_DEBUG` | `false` | Enable debug logging |

### YAML Config File

See `orchestrator.yaml` for the full config structure.

## REST API

Start the FastAPI server:

```bash
cd server
python -m uvicorn main:app --reload --port 8080
```

### Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/status` | Orchestrator status + latest analysis |
| GET | `/analysis/latest` | Most recent aggregated stress analysis |
| GET | `/analysis/history?limit=10` | Historical analyses |
| GET | `/messages?channel=discord&window=60` | Recent polled messages |
| GET | `/channels` | List active polling channels |
| GET | `/metrics` | Prometheus-style metrics |

### Example Response

```json
GET /analysis/latest

{
  "overall_stress_level": "moderate",
  "total_messages": 12,
  "total_unique_senders": 4,
  "crisis_flag": false,
  "total_urgent_items": 2,
  "top_themes_across_channels": ["deployment", "bug-fix", "customer-support"],
  "channel_breakdown": {
    "discord": {"count": 8, "unique_senders": 3},
    "gmail": {"count": 4, "unique_senders": 2}
  },
  "cycle_number": 42
}
```

## Project Structure

```
server/
├── __init__.py              # Package marker
├── main.py                  # FastAPI web server
├── run_orchestrator.py      # CLI runner
├── orchestrator.yaml        # Example YAML config
├── requirements.txt         # Dependencies
├── README.md                # This file
└── orchestrator/
    ├── __init__.py          # Package + exports
    ├── __main__.py          # python -m entry point
    ├── config.py            # All configuration dataclasses
    ├── storage.py           # Message store + rolling buffers
    ├── poller.py            # Discord & Gmail pollers
    ├── analyser.py          # LLM stress analysis engine
    └── orchestrator.py      # Main loop & coordination
```

## How It Works

### Poll Cycle (every 15 seconds)

1. **Phase 1 — Poll**: Both Discord and Gmail pollers fire concurrently via `asyncio.gather`. Each fetches new messages since the last poll using the OpenClaw gateway's RPC methods (`message.read` for Discord, `GmailConnector.list_messages` for email).

2. **Phase 2 — Store**: All new messages are normalised into a standard schema (id, text, sender, channel, timestamp, metadata) and stored in the thread-safe `RollingBuffer` and appended to channel-specific JSONL files.

3. **Phase 3 — Analyse**: The `StressAnalyser` takes the per-channel message batch and sends it to the OpenClaw LLM agent with a structured prompt asking for:
   - Stress level classification
   - Urgent item extraction
   - Volume trend analysis
   - Topic/sentiment extraction
   - Crisis flagging

4. **Phase 4 — Aggregate**: Per-channel analyses are combined into a cross-channel aggregated summary with worst-case stress level, total urgent count, and combined themes.

5. **Phase 5 — Emit**: The aggregated summary is printed to stdout, written to `latest_summary.json`, appended to the running summary file, and exposed via the REST API.

### LLM Analysis

The analysis prompt includes:
- Channel name and time window
- Message count and unique sender count
- Message rate (messages/minute)
- Condensed message texts (up to 8000 chars)

The LLM returns structured fields which are parsed via regex extraction.

### Fallback Engine

When the LLM agent is unavailable (gateway not paired, no model configured), the analyser falls back to a keyword-based engine that scans for:
- **Crisis keywords**: urgent, critical, emergency, blocked, broken, security, breach, etc.
- **Stress keywords**: overwhelmed, pressure, deadline, struggle, concern, etc.
- **Positive keywords**: great, awesome, done, completed, thanks, etc.

## Extending

### Adding a new channel poller

1. Create a new class inheriting from `BasePoller` in `poller.py`
2. Implement the `async def poll(self) -> list[dict]` method
3. Add the channel type to the `create_poller()` factory
4. Add settings to `config.py` (extend `OrchestratorConfig`)
5. Add the poller to `_init_pollers()` in `orchestrator.py`

### Using a different LLM

Set `NEUROSYNC_LLM_MODEL` to any model supported by OpenClaw, e.g.:
- `openai/gpt-4o`
- `anthropic/claude-3-opus`
- `openai/gpt-4o-mini` (default)
- `mistral/mixtral-8x7b`

## Troubleshooting

**"Gateway not reachable"**
```bash
openclaw gateway run --force
```

**"No device identity"**
```bash
openclaw onboard
```

**"Channel not configured"**
```bash
openclaw channels add --channel discord --token YOUR_TOKEN
openclaw channels status
```

**"LLM analysis failing"**
The fallback keyword engine will take over automatically. Check `openclaw models status` to verify model provider health.

## License

MIT — part of the NeuroSync project.