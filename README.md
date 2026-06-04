# Local Email Agent

A web-UI-first email triage assistant that runs entirely on your machine.

The browser UI in `ui/` is the primary interface. It's served by a small local
HTTP server (`api_server.py`) that talks to whatever LLM backend you configure
— **MLX** by default on macOS, but any OpenAI-compatible server (llama.cpp,
Ollama, LM Studio, vLLM) or cloud API (OpenAI, Anthropic) will work via
config.

The optional Mail.app / Calendar.app integration uses AppleScript and only
runs on macOS. The web UI itself is cross-platform — open it in any browser
to view your latest digest.

---

## Quick start (macOS, MLX)

```bash
# 1. Python deps
pip install -r requirements.txt

# 2. MLX LLM server (separate install)
pip install mlx-lm
python -m mlx_lm.server \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --port 8080

# 3. Start the API + UI server
python3 api_server.py

# 4. Open the UI
open http://127.0.0.1:8000/ui/
```

You should see `LLM backend: mlx  base_url=http://127.0.0.1:8080  ...` in the
server log. The browser UI loads against the live backend; if no digest exists
yet it falls back to mock data.

## Switching LLM backend

Either edit `config.json` (copy from `config.example.json`) or set env vars:

```bash
# Ollama
LLM_BACKEND=ollama LLM_BASE_URL=http://127.0.0.1:11434 \
  LLM_MODEL=llama3.2:3b-instruct-q4_K_M python3 api_server.py

# llama.cpp / LM Studio (any OpenAI-compatible /v1 endpoint)
LLM_BACKEND=openai_compatible LLM_BASE_URL=http://127.0.0.1:8080 \
  LLM_MODEL=local python3 api_server.py

# OpenAI cloud
LLM_BACKEND=openai LLM_API_KEY=sk-... LLM_MODEL=gpt-4o-mini python3 api_server.py

# Anthropic cloud
LLM_BACKEND=anthropic LLM_API_KEY=sk-ant-... \
  LLM_MODEL=claude-haiku-4-5-20251001 python3 api_server.py
```

`GET /api/llm-config` returns the active backend (without the API key) for
debugging.

## Run via Docker

Docker packages the **web layer only** (`api_server.py` + the `ui/` web app).
MLX and the macOS Mail/Calendar integration stay native on the host — a Linux
container can't access Apple Silicon's Metal GPU or `Mail.app`/`Calendar.app`.

```bash
# 1. Host (native): start MLX with Metal/GPU
python -m mlx_lm.server --model mlx-community/Llama-3.2-3B-Instruct-4bit --port 8080

# 2. (Optional, macOS) populate the digest from Mail.app
python3 agent_mail_calendar.py

# 3. Launch the webpage in Docker
docker compose up --build
# → open http://localhost:8000
```

How it fits together:

- The container binds `0.0.0.0:8000` and is published to `localhost:8000`.
- It reaches the host's MLX server via `host.docker.internal:8080`
  (`LLM_BASE_URL` in `docker-compose.yml`).
- `./logs` and `./state` are mounted, so the native worker's
  `latest_digest.json` shows up in the UI and todos/audit persist.
- Calendar **writes** need AppleScript, so inside the container
  `POST /api/calendar-events` returns `501` and the UI falls back to an `.ics`
  download. For real Calendar writes, run `python3 api_server.py` natively on
  the Mac instead of (or alongside) the container.

To use a cloud backend instead of host MLX, set `LLM_BACKEND`/`LLM_MODEL`/
`LLM_API_KEY` in `docker-compose.yml` (examples are in the file).

## What the agent does (macOS only)

`agent_mail_calendar.py` is the background worker:

1. Fetches unread mail from Mail.app via AppleScript
2. Sends each email to the LLM and parses a structured JSON response
3. Optionally creates a Calendar.app event when confidence is high enough
4. Writes a digest (`logs/latest_digest.json`) the web UI then displays
5. Optionally emails the digest to a configured address

Run it ad-hoc or on a schedule (e.g. via `launchd`):

```bash
python3 agent_mail_calendar.py
```

`agent_calendar_only.py` is a smaller demo that processes a hardcoded sample
email — useful for testing the LLM connection.

## File layout

| Path | Purpose |
|---|---|
| `ui/` | React/Babel-CDN web UI (no build step) |
| `api_server.py` | Local HTTP server, JSON APIs, static UI hosting |
| `agent_mail_calendar.py` | macOS background worker — Mail+Calendar agent |
| `agent_calendar_only.py` | Standalone calendar-only demo |
| `llm_client.py` | Pluggable LLM client (MLX / OpenAI-compatible / cloud) |
| `scripts/*.applescript` | macOS Mail/Calendar automation (worker only) |
| `config.example.json` | Example config; copy to `config.json` to use |

## Cross-platform note

On non-macOS systems you can still:

- Run `python3 api_server.py` and view the UI at `/ui/`
- Use the `/api/chat`, `/api/refine-event-time`, `/api/importance-explain`
  endpoints (all pure LLM)
- View any `latest_digest.json` produced elsewhere

You **cannot** use the AppleScript-backed routes (`/api/calendar-events`,
`/api/calendar-conflicts`) or run `agent_mail_calendar.py` — those need
Mail.app / Calendar.app.
