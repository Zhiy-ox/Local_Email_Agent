# Email Agent UI — Redesign

ASCII-terminal style email triage dashboard for the Local Email Agent.  
Built with React + JetBrains Mono. Connects to `api_server.py` at `http://127.0.0.1:8000`.

## Features

- **Action-oriented zones** — RESPOND / DECIDE / SCHEDULE / INBOX — organises emails by *what to do*, not read status
- **Compose reply modal** — Pix drafts a reply via local LLM; edit and send via `mailto:` or copy to clipboard
- **Apple Calendar integration** — `[→ Apple Calendar]` posts to `/api/calendar-events` (AppleScript); falls back to `.ics` download when server is offline
- **Live backend** — auto-probes `http://127.0.0.1:8000`; gracefully degrades to mock data when offline
- **3 themes** — `DARK.TERM` / `PAPER.TERM` / `AMBER.TERM` — switchable via Tweaks panel
- **Pix chat** — talks to local LLM via `/api/chat`; falls back to Claude sandbox

## Usage

```bash
# Start the backend
python api_server.py

# Open the UI (served by the backend)
open http://127.0.0.1:8000/ui/
```

Or open `email-agent/Email Agent (Standalone).html` directly in any browser — no server required (uses mock data + Claude sandbox for Pix).

## File structure

```
email-agent/
  Email Agent.html          ← entry point (loads the files below)
  data.js                   ← mock data, themes, API client, ICS generator
  components.jsx            ← all React components
  app.jsx                   ← main App, zone layout, state
  Email Agent (Standalone).html  ← self-contained offline bundle
```

## API endpoints used

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/digest` | Load emails |
| POST | `/api/chat` | Pix chat (local LLM) |
| POST | `/api/calendar-events` | Create Apple Calendar event via AppleScript |
| POST | `/api/refine-event-time` | Ask LLM to refine event datetime |
| POST | `/api/snooze` | Snooze an email |
