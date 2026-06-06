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

## First real run (macOS, with your own email)

This is the end-to-end path to a live feed of your real email.

```bash
# 0. Python deps
pip install -r requirements.txt

# 1. Start a local LLM that serves an OpenAI-compatible API on port 8080.
#    Use whatever you like — e.g. the vMLX app, or mlx_lm:
#      pip install mlx-lm
#      python -m mlx_lm.server --model mlx-community/Llama-3.2-3B-Instruct-4bit --port 8080
#    If your server uses a different port, set LLM_BASE_URL (see below).

# 2. Verify everything is wired up (LLM reachable, scripts present, Mail visible)
python3 check_setup.py

# 3. Triage your real unread mail -> writes logs/latest_digest.json
python3 agent_mail_calendar.py

# 4. Serve the UI
python3 api_server.py

# 5. Open it
open http://127.0.0.1:8000/ui/
```

**Permissions (first run only):** the worker controls Mail and Calendar via
AppleScript, so macOS will prompt for Automation access. Approve it, or set it
manually in **System Settings → Privacy & Security → Automation** (allow your
terminal to control **Mail** and **Calendar**). `check_setup.py` triggers the
Mail prompt early so you don't hit it mid-run.

What the worker does on a real run:

- Pulls unread mail from **all** your Mail.app accounts (school + personal).
- Sends each email to your local LLM and parses a structured result.
- Auto-creates a **"AI Drafts"** calendar (if missing) and drops high-confidence
  events there for you to review — your other calendars are untouched.
- Writes `logs/latest_digest.json`, which the UI reads. (No email is sent; the
  digest is UI-only.)
- Marks processed emails read so the next run surfaces the next batch — flip
  `MARK_AS_READ = False` in `agent_mail_calendar.py` to disable that.

Re-run step 3 anytime to refresh; hit **▶ refresh digest** in the UI to reload.
`GET /api/health` reports whether the LLM is reachable.

### Pointing at vMLX (or any non-default port)

If your LLM isn't on `http://127.0.0.1:8080`, set the base URL once:

```bash
export LLM_BASE_URL=http://127.0.0.1:<port>
python3 check_setup.py     # should now show "Local LLM reachable"
```

`check_setup.py` and the worker both refuse to run until the LLM answers, so
you'll get a clear message instead of a stalled triage.

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

## What the agent does (macOS only)

`agent_mail_calendar.py` is the background worker:

1. Fetches unread mail from **all** Mail.app accounts via AppleScript
2. Sends each email to the LLM and parses a structured JSON response
3. Creates a Calendar.app event in the auto-created "AI Drafts" calendar when
   confidence is high enough
4. Writes a digest (`logs/latest_digest.json`) the web UI then displays
   (UI-only — no email is sent)

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
| `check_setup.py` | Preflight diagnostic (LLM, scripts, Mail access) |
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
