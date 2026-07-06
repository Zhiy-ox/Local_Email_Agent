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

## Quick start — one click (macOS, MLX)

Double-click **`start.command`** in Finder. That's it. It will:

1. Create `config.json` from `config.example.json` (first run only)
2. Create a `.venv` and install dependencies (first run only)
3. Start the MLX server with the model from `config.json`
   (reused if one is already running at the configured `base_url`)
4. Start `api_server.py` and open <http://127.0.0.1:8000/ui/> in your browser

Stop everything with **`stop.command`**. To also process your unread mail
immediately on startup, run `./start.command --run-agent` from a terminal —
or just click **`▶ run agent`** in the web UI's top bar.

> First run: macOS may block the double-click (unidentified developer).
> Right-click → Open once, or run `./start.command` from Terminal.
> The first MLX start also downloads the model from Hugging Face.

Set your model in `config.json` → `llm.model` (e.g. your Qwen 4-bit MLX
build such as `mlx-community/Qwen3-4B-Instruct-2507-4bit`); `start.command`
launches `mlx_lm.server` with exactly that id.

<details>
<summary>Manual start (what the script does under the hood)</summary>

```bash
# 1. Python deps
pip install -r requirements.txt

# 2. MLX LLM server (separate install)
pip install mlx-lm
python -m mlx_lm.server \
  --model mlx-community/Qwen3-4B-Instruct-2507-4bit \
  --port 8080

# 3. Start the API + UI server
python3 api_server.py

# 4. Open the UI
open http://127.0.0.1:8000/ui/
```

</details>

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
debugging. `GET /api/health` additionally probes whether the LLM server is
reachable and reports agent-run status.

## What the agent does (macOS only)

`agent_mail_calendar.py` is the background worker:

1. Fetches unread mail from Mail.app via AppleScript
2. Sends each email to the LLM and parses a structured JSON response
3. Optionally creates a Calendar.app event when confidence is high enough
4. Writes a digest (`logs/latest_digest.json`) the web UI then displays
5. Optionally emails the digest to a configured address

Three ways to run it:

- Click **`▶ run agent`** in the web UI (calls `POST /api/run-agent`;
  progress via `GET /api/agent-status`, log in `logs/agent_run.log`)
- `python3 agent_mail_calendar.py` ad-hoc from a terminal
- On a schedule via `launchd` / cron

Agent behaviour is configured in `config.json` under `"agent"` (or via
`AGENT_*` env vars):

| Key | Env var | Default | Meaning |
|---|---|---|---|
| `timezone` | `AGENT_TIMEZONE` | `Europe/London` | Target timezone for events |
| `confidence_threshold` | `AGENT_CONF_THRESHOLD` | `0.85` | Min LLM confidence to auto-create an event |
| `max_unread` | `AGENT_MAX_UNREAD` | `10` | Max unread emails per run |
| `max_body_chars` | `AGENT_MAX_BODY_CHARS` | `5000` | Truncate email bodies beyond this |
| `send_digest_email` | `AGENT_SEND_DIGEST` | `true` | Email the digest after each run |
| `digest_to` | `AGENT_DIGEST_TO` | — | Digest recipient (empty disables sending) |

`agent_calendar_only.py` is a smaller demo that processes a hardcoded sample
email — useful for testing the LLM connection.

## File layout

| Path | Purpose |
|---|---|
| `start.command` | One-click launcher: venv + MLX server + API server + browser |
| `stop.command` | Stops what `start.command` started |
| `ui/` | React/Babel-CDN web UI (no build step) |
| `EmailAgentUI/` | Native macOS app (SwiftUI) — see its README |
| `api_server.py` | Local HTTP server, JSON APIs, static UI hosting |
| `agent_mail_calendar.py` | macOS background worker — Mail+Calendar agent |
| `agent_calendar_only.py` | Standalone calendar-only demo |
| `llm_client.py` | Pluggable LLM client (MLX / OpenAI-compatible / cloud) |
| `scripts/*.applescript` | macOS Mail/Calendar automation (worker only) |
| `config.example.json` | Example config; copy to `config.json` to use |

## Native macOS app (SwiftUI)

`EmailAgentUI/` is a native Mac client for the same backend. Double-click
`EmailAgentUI/build_app.command` to compile and launch `Email Agent.app`
(needs Xcode Command Line Tools). It has the same triage zones as the web
UI, a Run Agent button with live progress, one-click Add to Apple Calendar,
Pix chat, and a **Start Backend** button that runs `start.command` for you
when the server is offline — so the app itself becomes the single click.
See `EmailAgentUI/README.md`.

## Cross-platform note

On non-macOS systems you can still:

- Run `python3 api_server.py` and view the UI at `/ui/`
- Use the `/api/chat`, `/api/refine-event-time`, `/api/importance-explain`
  endpoints (all pure LLM)
- View any `latest_digest.json` produced elsewhere

You **cannot** use the AppleScript-backed routes (`/api/calendar-events`,
`/api/calendar-conflicts`) or run `agent_mail_calendar.py` — those need
Mail.app / Calendar.app.
