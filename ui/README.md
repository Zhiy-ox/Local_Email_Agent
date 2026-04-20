# Email Agent UI (React + Local API)

This is a local React control room with a pixel-robot assistant (Pix) talking to your local model.

## Start

1. Generate digest artifacts:

```bash
cd "/Users/xuzhiyu/Documents/Codex_/Email_AI_agent /ai_email_agent_Codex"
python3 agent_mail_calendar.py
```

2. Start local API + static server (single process):

```bash
cd "/Users/xuzhiyu/Documents/Codex_/Email_AI_agent /ai_email_agent_Codex"
python3 api_server.py
```

3. Open:

- `http://127.0.0.1:8000/ui/`

## Implemented features

- Digest API (`GET /api/digest`) using `latest_digest.json` with text fallback
- Local model chat (`POST /api/chat`) shown as pixel robot assistant
- Calendar safety guardrails (required fields, confidence, datetime sanity, conflict check)
- Calendar conflict detector (`POST /api/calendar-conflicts`)
- Calendar create endpoint (`POST /api/calendar-events`)
- Review workflow (queue + batch approve/reject + CSV audit export)
- Time refinement endpoint (`POST /api/refine-event-time`)
- Importance explanation endpoint (`POST /api/importance-explain`)
- Snooze endpoint (`POST /api/snooze`)
- Todo endpoint (`GET/POST /api/todos`)
- Daily/weekly analytics (`GET /api/analytics`)

## Notes

- Pix chat and refinement rely on your local OpenAI-compatible model endpoint at:
  - `http://127.0.0.1:8080/v1/chat/completions`
- Calendar actions use Apple Calendar via AppleScript in `scripts/create_event.applescript`.
