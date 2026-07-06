#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# One-click launcher for the Local Email Agent.
#
#   Double-click this file in Finder (macOS), or run ./start.command
#
# What it does, in order:
#   1. Creates config.json from config.example.json on first run
#   2. Creates a Python virtualenv (.venv) and installs dependencies
#   3. Starts the MLX LLM server with the model from config.json
#      (skipped if something is already answering at the configured base_url)
#   4. Starts api_server.py (UI + JSON APIs) on http://127.0.0.1:8000
#   5. Opens the web UI in your browser
#
# Optional: ./start.command --run-agent  also triggers one mail-processing
# run immediately after startup (same as the "run agent" button in the UI).
#
# Stop everything with ./stop.command
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

cd "$(dirname "$0")"

APP_URL="http://127.0.0.1:8000"
RUN_AGENT=0
[[ "${1:-}" == "--run-agent" ]] && RUN_AGENT=1

mkdir -p logs state

say() { printf '\033[1;36m[email-agent]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[email-agent]\033[0m %s\n' "$*"; }

# ── 1. Config ────────────────────────────────────────────────────────────────
if [[ ! -f config.json ]]; then
  cp config.example.json config.json
  say "Created config.json from config.example.json."
  say "Edit \"llm.model\" in config.json to change the model (e.g. your Qwen 4-bit MLX build)."
fi

# ── 2. Python env ────────────────────────────────────────────────────────────
if [[ ! -d .venv ]]; then
  say "Creating Python virtualenv (.venv) — first run only..."
  python3 -m venv .venv
fi
# shellcheck disable=SC1091
source .venv/bin/activate

if ! python -c "import requests" >/dev/null 2>&1; then
  say "Installing Python dependencies..."
  pip install --quiet --upgrade pip
  pip install --quiet -r requirements.txt
fi

# Resolve the effective LLM config (config.json merged with LLM_* env vars)
LLM_CFG=$(python -c "import json; from llm_client import describe_config; print(json.dumps(describe_config()))")
BACKEND=$(python  -c "import sys,json; print(json.loads(sys.argv[1])['backend'])"  "$LLM_CFG")
BASE_URL=$(python -c "import sys,json; print(json.loads(sys.argv[1])['base_url'])" "$LLM_CFG")
MODEL=$(python    -c "import sys,json; print(json.loads(sys.argv[1])['model'])"    "$LLM_CFG")

say "LLM backend: $BACKEND  model: $MODEL  url: $BASE_URL"

llm_up() { curl -s -o /dev/null --max-time 2 "$BASE_URL/v1/models"; }

# ── 3. LLM server (MLX) ──────────────────────────────────────────────────────
if [[ "$BACKEND" == "mlx" ]]; then
  if llm_up; then
    say "MLX server already running at $BASE_URL — reusing it."
  elif [[ "$(uname -s)" != "Darwin" ]]; then
    warn "MLX requires Apple Silicon macOS — skipping LLM server start."
    warn "Point config.json at another backend (ollama/llamacpp) on this machine."
  else
    if ! python -c "import mlx_lm" >/dev/null 2>&1; then
      say "Installing mlx-lm — first run only..."
      pip install --quiet mlx-lm
    fi
    MLX_PORT=$(python -c "import sys; from urllib.parse import urlparse; print(urlparse(sys.argv[1]).port or 8080)" "$BASE_URL")
    say "Starting MLX server: $MODEL on port $MLX_PORT (log: logs/mlx_server.log)"
    nohup python -m mlx_lm.server --model "$MODEL" --port "$MLX_PORT" \
      >> logs/mlx_server.log 2>&1 &
    echo $! > state/mlx_server.pid

    say "Waiting for the model to load (first run downloads it from Hugging Face — can take a while)..."
    MLX_PID=$(cat state/mlx_server.pid)
    up=0
    for i in $(seq 1 900); do            # up to 30 minutes for a first download
      if llm_up; then up=1; break; fi
      if ! kill -0 "$MLX_PID" 2>/dev/null; then
        warn "MLX server exited unexpectedly. Last log lines:"
        tail -n 20 logs/mlx_server.log || true
        exit 1
      fi
      if (( i % 15 == 0 )); then
        say "  still loading... ($((i * 2))s elapsed — run 'tail -f logs/mlx_server.log' for detail)"
      fi
      sleep 2
    done
    if [[ "$up" == 1 ]]; then
      say "MLX server is up."
    else
      warn "Timed out waiting for the MLX server; continuing anyway (check logs/mlx_server.log)."
    fi
  fi
else
  if llm_up; then
    say "LLM backend reachable at $BASE_URL."
  else
    warn "LLM backend '$BACKEND' is not answering at $BASE_URL — start it, or the UI will fall back to mock data."
  fi
fi

# ── 4. API + UI server ───────────────────────────────────────────────────────
api_up() { curl -s -o /dev/null --max-time 2 "$APP_URL/api/llm-config"; }

if api_up; then
  say "API server already running at $APP_URL — reusing it."
else
  say "Starting API server at $APP_URL (log: logs/api_server.log)"
  nohup python api_server.py >> logs/api_server.log 2>&1 &
  echo $! > state/api_server.pid
  for _ in $(seq 1 30); do
    api_up && break
    sleep 1
  done
  if ! api_up; then
    warn "API server did not come up. Last log lines:"
    tail -n 20 logs/api_server.log || true
    exit 1
  fi
  say "API server is up."
fi

# ── 5. Optional immediate agent run + open browser ──────────────────────────
if [[ "$RUN_AGENT" == 1 ]]; then
  say "Triggering a mail-processing run (POST /api/run-agent)..."
  curl -s -X POST "$APP_URL/api/run-agent" -H 'Content-Type: application/json' -d '{}' || true
  echo
fi

say "Ready → $APP_URL/ui/"
if command -v open >/dev/null 2>&1; then
  open "$APP_URL/ui/"
elif command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$APP_URL/ui/" >/dev/null 2>&1 || true
fi

say "Servers keep running in the background — you can close this window."
say "To stop them later: ./stop.command"
