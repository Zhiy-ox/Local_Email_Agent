#!/usr/bin/env bash
# Stops the servers started by start.command (double-click or ./stop.command).
# Only touches processes whose PIDs were recorded by start.command — an MLX
# server you launched yourself is left alone.
set -uo pipefail

cd "$(dirname "$0")"

stopped=0

stop_pid_file() {
  local file="$1" name="$2"
  [[ -f "$file" ]] || return 0
  local pid
  pid=$(cat "$file" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null && echo "Stopped $name (pid $pid)"
    stopped=1
  else
    echo "$name was not running."
  fi
  rm -f "$file"
}

stop_pid_file state/api_server.pid "API server"
stop_pid_file state/mlx_server.pid "MLX server"

if [[ "$stopped" == 0 ]]; then
  echo "Nothing recorded by start.command was running."
fi

if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:8000/api/llm-config"; then
  echo "Note: something is still listening on port 8000 (started outside start.command)."
fi
