#!/usr/bin/env bash
# ===========================================================================
# NeuroSync Demo Launcher
#
# Starts the simulator server and main server so the iOS app can pull feeds.
# The main server starts with NEUROSYNC_SIM_MODE=true so it uses
# SimulatedHttpPoller to fetch messages from the simulator server.
#
# Usage:
#   bash launch_demo.sh
#   bash launch_demo.sh --scenario crisis_spike
#   bash launch_demo.sh --port 8080 --sim-port 8081
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ---- Kill stale processes on common ports ----
for _port in 8080 8081; do
    _pid=$(lsof -ti:"$_port" 2>/dev/null || true)
    if [ -n "$_pid" ]; then
        echo "  ⚠ Port $_port in use by PID $_pid — killing it"
        kill "$_pid" 2>/dev/null || true
        sleep 1
    fi
done

# ---- Defaults ----
MAIN_PORT=8080
SIM_PORT=8081
SCENARIO="normal_day"
SEED=42
TOTAL_MSGS=1000

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port) MAIN_PORT="$2"; shift 2 ;;
        --sim-port) SIM_PORT="$2"; shift 2 ;;
        --scenario) SCENARIO="$2"; shift 2 ;;
        --seed) SEED="$2"; shift 2 ;;
        --total-messages) TOTAL_MSGS="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--port PORT] [--sim-port PORT] [--scenario NAME] [--seed N] [--total-messages N]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---- Detect local IP for iOS app ----
LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || ifconfig en0 | grep 'inet ' | awk '{print $2}' || echo "127.0.0.1")
if [ "$LOCAL_IP" = "127.0.0.1" ]; then
    # Try en1 (common on Mac laptops)
    LOCAL_IP=$(ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
fi

cleanup() {
    echo ""
    echo "🛑 Shutting down..."
    if [ -n "${SIM_PID:-}" ]; then
        kill "$SIM_PID" 2>/dev/null || true
        wait "$SIM_PID" 2>/dev/null || true
        echo "  Simulator server stopped (PID $SIM_PID)"
    fi
    if [ -n "${MAIN_PID:-}" ]; then
        kill "$MAIN_PID" 2>/dev/null || true
        wait "$MAIN_PID" 2>/dev/null || true
        echo "  Main server stopped (PID $MAIN_PID)"
    fi
    echo "✅ Done."
    exit 0
}
trap cleanup SIGINT SIGTERM

# ---- Check Python deps ----
echo "🔍 Checking Python dependencies..."
python3 -c "import fastapi, uvicorn, httpx" 2>/dev/null || {
    echo "Installing Python dependencies..."
    pip install -r requirements.txt
}
echo "  ✓ Dependencies OK"

# ---- Start simulator server ----
echo ""
echo "🎮 Starting simulator server on port $SIM_PORT (scenario: $SCENARIO)..."
python3 simulator_server.py \
    --port "$SIM_PORT" \
    --scenario "$SCENARIO" \
    --seed "$SEED" \
    --total-messages "$TOTAL_MSGS" \
    > /dev/null 2>&1 &
SIM_PID=$!

# Wait for simulator to be ready
for i in $(seq 1 15); do
    if curl -sf "http://127.0.0.1:$SIM_PORT/health" > /dev/null 2>&1; then
        echo "  ✓ Simulator server ready (PID $SIM_PID)"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "  ✗ Simulator server failed to start"
        cleanup
    fi
    sleep 0.5
done

# ---- Start main server ----
echo ""
echo "🚀 Starting main server on port $MAIN_PORT (SIM_MODE=true)..."
NEUROSYNC_SIM_MODE=true \
NEUROSYNC_SIMULATOR_URL="http://127.0.0.1:$SIM_PORT" \
    python3 -m uvicorn main:app \
        --host 0.0.0.0 \
        --port "$MAIN_PORT" \
        --log-level error &
MAIN_PID=$!

# Wait for main server to be ready
for i in $(seq 1 15); do
    if curl -sf "http://127.0.0.1:$MAIN_PORT/health" > /dev/null 2>&1; then
        echo "  ✓ Main server ready (PID $MAIN_PID)"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "  ✗ Main server failed to start"
        cleanup
    fi
    sleep 0.5
done

# ---- Print connection info ----
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ NeuroSync Demo is RUNNING"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  iOS App Configuration:"
echo "    Server URL:  http://$LOCAL_IP:$MAIN_PORT"
echo ""
echo "  Local Endpoints:"
echo "    Main server:    http://127.0.0.1:$MAIN_PORT"
echo "    Dashboard:      http://127.0.0.1:$MAIN_PORT/social/dashboard"
echo "    Health:         http://127.0.0.1:$MAIN_PORT/health"
echo "    Simulator API:  http://127.0.0.1:$SIM_PORT/sim/status"
echo ""
echo "  Simulator Controls:"
echo "    Change scenario: curl -X POST http://127.0.0.1:$SIM_PORT/sim/scenario?scenario=crisis_spike"
echo "    Stop sim:        curl -X POST http://127.0.0.1:$SIM_PORT/sim/stop"
echo "    Start sim:       curl -X POST http://127.0.0.1:$SIM_PORT/sim/start -H 'Content-Type: application/json' -d '{\"scenario\":\"incident_escalation\"}'"
echo ""
echo "  Available scenarios: normal_day, incident_escalation, weekend_calm,"
echo "                       crisis_spike, gradual_buildup, rollercoaster,"
echo "                       sustained_pressure"
echo ""
echo "  Press Ctrl+C to stop both servers."
echo "═══════════════════════════════════════════════════════════════"

# Wait for either process to exit
wait
