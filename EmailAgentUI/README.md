# Email Agent — native macOS app (SwiftUI)

A native SwiftUI client for the Local Email Agent backend (`api_server.py`).
Same triage model as the web UI — RESPOND / DECIDE / SCHEDULE / INBOX — as a
real Mac app.

## Features

- **Triage list** grouped into action zones, with importance tags and summaries
- **Run Agent** button — triggers `POST /api/run-agent` on the backend and
  live-polls until the mail run finishes, then reloads the digest
- **Detail pane** — summary, action items (→ Todos), detected event with
  one-click **Add to Apple Calendar**, Done / Snooze (1h · tomorrow · next week)
- **Pix chat** — talks to your local LLM via `/api/chat`
- **Status bar** — zone counts, LLM backend/model reachability dot, last
  agent-run log popover
- **Start Backend** — if the server is offline, one button runs the repo's
  `start.command` for you (asks for the repo folder once, then remembers it)

## Build & run (one click)

Double-click **`build_app.command`** (or run it in a terminal). It compiles
the package in release mode, wraps it into `build/Email Agent.app`, ad-hoc
signs it, and launches it. Drag the app into `/Applications` to keep it.

Requires Xcode or the Command Line Tools (`xcode-select --install`),
macOS 13+.

Alternatives:

```bash
swift run                 # run directly from the package
open Package.swift        # open in Xcode and hit ⌘R
```

## Configuration

Preferences (⌘,) let you change the backend URL (default
`http://127.0.0.1:8000`). The repo folder used by "Start Backend" is stored
after you pick it the first time.
