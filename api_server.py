import csv
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Optional
from urllib.parse import parse_qs, urlparse

import requests

from llm_client import describe_config, get_llm_client, ping

TIMEZONE = "Europe/London"
HOST = "127.0.0.1"
PORT = 8000

BASE = Path(__file__).resolve().parent
SCRIPTS = BASE / "scripts"
LOGS = BASE / "logs"
STATE = BASE / "state"
UI = BASE / "ui"

DIGEST_JSON_FILE = LOGS / "latest_digest.json"
DIGEST_TXT_FILE = LOGS / "latest_digest.txt"
HISTORY_FILE = LOGS / "digest_history.jsonl"
TODO_FILE = STATE / "todos.json"
SNOOZE_FILE = STATE / "snoozed.json"
REVIEW_FILE = STATE / "review_queue.json"
AUDIT_FILE = LOGS / "review_audit.jsonl"

SCRIPT_CREATE_EVENT = SCRIPTS / "create_event.applescript"


def now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def ensure_dirs() -> None:
    LOGS.mkdir(parents=True, exist_ok=True)
    STATE.mkdir(parents=True, exist_ok=True)


def applescript_available() -> bool:
    """True only on a macOS host with osascript — never inside the Linux container."""
    return sys.platform == "darwin" and shutil.which("osascript") is not None


def parse_stats_line(line: str) -> dict:
    import re

    m = re.search(
        r"Processed:\s*(\d+)\s*\|\s*Created events:\s*(\d+)\s*\|\s*Not created:\s*(\d+)\s*\|\s*Failed:\s*(\d+)",
        line or "",
    )
    if not m:
        return {"processed": 0, "created": 0, "not_created": 0, "failed": 0}
    return {
        "processed": int(m.group(1)),
        "created": int(m.group(2)),
        "not_created": int(m.group(3)),
        "failed": int(m.group(4)),
    }


def parse_digest_text(text: str) -> dict:
    import re

    lines = text.splitlines()
    header = lines[0] if lines else "AI Email Digest"
    stats_line = next((l for l in lines if "Processed:" in l), "")
    stats = parse_stats_line(stats_line)

    items = []
    current = None

    for line in lines:
        entry = re.match(r"^\[(\d+)\]\s+Importance:\s*(\d+)\s*\|\s*(.*?)\s*\|\s*(.*)$", line)
        if entry:
            if current:
                items.append(current)
            current = {
                "idx": int(entry.group(1)),
                "importance": int(entry.group(2)),
                "sender": entry.group(3).strip(),
                "subject": entry.group(4).strip(),
                "date": "",
                "summary": "",
                "action_items": [],
                "calendar_result": "",
                "event_preview": "",
                "event": None,
                "message_id": "",
                "body_preview": "",
            }
            continue

        if not current:
            continue

        s = line.strip()
        if s.startswith("Date:"):
            current["date"] = s.split("Date:", 1)[1].strip()
        elif s.startswith("Summary:"):
            current["summary"] = s.split("Summary:", 1)[1].strip()
        elif s.startswith("Calendar:"):
            current["calendar_result"] = s.split("Calendar:", 1)[1].strip()
        elif s.startswith("Event preview:"):
            current["event_preview"] = s.split("Event preview:", 1)[1].strip()
        elif s.startswith("-"):
            current["action_items"].append(s[1:].strip())

    if current:
        items.append(current)

    for item in items:
        item["event"] = extract_event_from_preview(item)

    return {
        "meta": {"generated_at": header, "timezone": TIMEZONE, "source": "text_fallback"},
        "stats": stats,
        "items": items,
    }


def load_digest() -> dict:
    if DIGEST_JSON_FILE.exists():
        with DIGEST_JSON_FILE.open("r", encoding="utf-8") as f:
            data = json.load(f)
        for item in data.get("items", []):
            if not item.get("event"):
                item["event"] = extract_event_from_preview(item)
            item.setdefault("message_id", "")
            item.setdefault("body_preview", "")
        return data

    if DIGEST_TXT_FILE.exists():
        return parse_digest_text(DIGEST_TXT_FILE.read_text(encoding="utf-8"))

    return {
        "meta": {"generated_at": now_str(), "timezone": TIMEZONE, "source": "none"},
        "stats": {"processed": 0, "created": 0, "not_created": 0, "failed": 0},
        "items": [],
    }


def extract_event_from_preview(item: dict) -> Optional[dict]:
    import re

    raw = (item.get("event_preview") or "").strip()
    if not raw:
        return None

    direct = re.match(
        r"(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})[–-](\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\s*@\s*(.*)$",
        raw,
    )
    if direct:
        return {
            "title": item.get("subject", "Email Event"),
            "start_datetime": direct.group(1),
            "end_datetime": direct.group(2),
            "timezone": TIMEZONE,
            "location": direct.group(3),
            "notes": item.get("summary", ""),
            "confidence": 0.9,
        }

    keyed = re.match(r"title=(.*?),\s*start=(.*?),\s*end=(.*?),\s*tz=(.*)$", raw)
    if keyed:
        return {
            "title": keyed.group(1).strip(),
            "start_datetime": keyed.group(2).strip(),
            "end_datetime": keyed.group(3).strip(),
            "timezone": keyed.group(4).strip() or TIMEZONE,
            "location": "",
            "notes": item.get("summary", ""),
            "confidence": 0.85,
        }

    return None


def load_json_file(path: Path, fallback):
    if not path.exists():
        return fallback
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return fallback


def save_json_file(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def append_jsonl(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def to_macos_datestr(dt_str: str) -> str:
    d = datetime.fromisoformat(dt_str)
    return d.strftime("%d %B %Y %H:%M:%S")


def create_event_local(event: dict) -> None:
    cmd = [
        "osascript",
        str(SCRIPT_CREATE_EVENT),
        event.get("title", "Event"),
        to_macos_datestr(event["start_datetime"]),
        to_macos_datestr(event["end_datetime"]),
        event.get("location", ""),
        event.get("notes", ""),
    ]
    subprocess.run(cmd, check=True)


def get_calendar_conflicts(event: dict) -> list[dict]:
    start_s = to_macos_datestr(event["start_datetime"])
    end_s = to_macos_datestr(event["end_datetime"])

    applescript = """
    on run argv
      set startStr to item 1 of argv
      set endStr to item 2 of argv
      set startDate to date startStr
      set endDate to date endStr
      set outItems to {}

      tell application "Calendar"
        repeat with c in calendars
          set evs to (every event of c whose (start date < endDate) and (end date > startDate))
          repeat with e in evs
            set s to start date of e
            set t to end date of e
            set one to (summary of e) & "|" & (s as string) & "|" & (t as string) & "|" & (name of c)
            copy one to end of outItems
          end repeat
        end repeat
      end tell

      set AppleScript's text item delimiters to "\\n"
      return outItems as string
    end run
    """.strip()

    cmd = ["osascript", "-e", applescript, start_s, end_s]
    out = subprocess.check_output(cmd).decode("utf-8", errors="replace").strip()
    if not out:
      return []

    conflicts = []
    for line in out.splitlines():
        parts = line.split("|")
        if len(parts) >= 4:
            conflicts.append(
                {
                    "title": parts[0],
                    "start": parts[1],
                    "end": parts[2],
                    "calendar": parts[3],
                }
            )
    return conflicts


def guardrail_check(event: dict) -> tuple[bool, str]:
    required = ["title", "start_datetime", "end_datetime"]
    missing = [k for k in required if not str(event.get(k, "")).strip()]
    if missing:
        return False, f"missing required fields: {missing}"

    try:
        s = datetime.fromisoformat(event["start_datetime"])
        e = datetime.fromisoformat(event["end_datetime"])
    except Exception:
        return False, "datetime parse failed"

    if e <= s:
        return False, "end must be after start"

    conf = float(event.get("confidence", 1.0) or 0.0)
    if conf < 0.8:
        return False, f"confidence too low ({conf:.2f})"

    conflicts = get_calendar_conflicts(event)
    if conflicts:
        return False, "calendar conflict detected"

    return True, "ok"


def llm_chat(messages: list[dict], temperature: float = 0.2) -> str:
    return get_llm_client().chat(messages, temperature=temperature)


def safe_json_load(s: str) -> dict:
    text = (s or "").strip()
    if text.startswith("```"):
        text = text.replace("```json", "").replace("```", "").strip()
    try:
        return json.loads(text)
    except Exception:
        start = text.find("{")
        end = text.rfind("}")
        if start >= 0 and end > start:
            return json.loads(text[start : end + 1])
        raise


def refine_event_time(payload: dict) -> dict:
    system = (
        "Output EXACTLY one JSON object with keys: title,start_datetime,end_datetime,timezone,location,notes,confidence,reason. "
        "Use format YYYY-MM-DD HH:MM:SS. No markdown. If unknown, keep fields empty and confidence low."
    )
    user = json.dumps(payload, ensure_ascii=False)
    out = llm_chat([
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ])
    data = safe_json_load(out)
    data.setdefault("timezone", TIMEZONE)
    return data


def explain_importance(payload: dict) -> dict:
    system = (
        "You explain why an email importance score should be 0-3. "
        "Return JSON: {importance:int, rationale:string, urgency:string, next_step:string}."
    )
    out = llm_chat([
        {"role": "system", "content": system},
        {"role": "user", "content": json.dumps(payload, ensure_ascii=False)},
    ])
    return safe_json_load(out)


def build_review_queue() -> list[dict]:
    digest = load_digest()
    rows = []
    for item in digest.get("items", []):
        if not item.get("event"):
            continue
        rows.append(
            {
                "idx": item.get("idx"),
                "subject": item.get("subject", ""),
                "sender": item.get("sender", ""),
                "event": item.get("event"),
                "status": "pending",
                "note": "",
            }
        )
    return rows


def get_or_init_review_queue() -> list[dict]:
    current = load_json_file(REVIEW_FILE, [])
    if current:
        return current
    current = build_review_queue()
    save_json_file(REVIEW_FILE, current)
    return current


def upsert_todos(items: list[dict]) -> dict:
    todos = load_json_file(TODO_FILE, [])
    added = 0
    for it in items:
        title = (it.get("title") or "").strip()
        if not title:
            continue
        row = {
            "id": f"todo-{int(datetime.now().timestamp() * 1000)}-{added}",
            "title": title,
            "source": it.get("source", "digest"),
            "provider": it.get("provider", "local"),
            "created_at": now_str(),
            "done": False,
        }
        todos.append(row)
        added += 1
    save_json_file(TODO_FILE, todos)
    return {"added": added, "total": len(todos)}


def save_snooze(item: dict) -> dict:
    rows = load_json_file(SNOOZE_FILE, [])
    rows.append(item)
    save_json_file(SNOOZE_FILE, rows)
    return {"count": len(rows)}


def get_analytics() -> dict:
    rows = []
    if HISTORY_FILE.exists():
        for line in HISTORY_FILE.read_text(encoding="utf-8").splitlines():
            try:
                rows.append(json.loads(line))
            except Exception:
                continue

    if not rows:
        d = load_digest()
        rows = [{"ts": now_str(), "stats": d.get("stats", {}), "items": d.get("items", [])}]

    cutoff_day = datetime.now() - timedelta(days=1)
    cutoff_week = datetime.now() - timedelta(days=7)

    daily = {"processed": 0, "created": 0, "failed": 0, "urgent": 0}
    weekly = {"processed": 0, "created": 0, "failed": 0, "urgent": 0}
    sender_counts = {}

    for row in rows:
        ts_text = row.get("ts") or row.get("meta", {}).get("generated_at") or now_str()
        try:
            ts = datetime.fromisoformat(ts_text.replace("Z", ""))
        except Exception:
            ts = datetime.now()

        stats = row.get("stats", {})
        urgent_count = 0
        for item in row.get("items", []):
            if int(item.get("importance", 0) or 0) >= 2:
                urgent_count += 1
            sender = item.get("sender", "")
            if sender:
                sender_counts[sender] = sender_counts.get(sender, 0) + 1

        if ts >= cutoff_day:
            daily["processed"] += int(stats.get("processed", 0) or 0)
            daily["created"] += int(stats.get("created", 0) or 0)
            daily["failed"] += int(stats.get("failed", 0) or 0)
            daily["urgent"] += urgent_count

        if ts >= cutoff_week:
            weekly["processed"] += int(stats.get("processed", 0) or 0)
            weekly["created"] += int(stats.get("created", 0) or 0)
            weekly["failed"] += int(stats.get("failed", 0) or 0)
            weekly["urgent"] += urgent_count

    top_senders = sorted(sender_counts.items(), key=lambda x: x[1], reverse=True)[:8]
    return {
        "daily": daily,
        "weekly": weekly,
        "top_senders": [{"sender": s, "count": c} for s, c in top_senders],
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "EmailAgentLocal/1.0"

    def _send_json(self, payload: dict, status=HTTPStatus.OK):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, body: str, status=HTTPStatus.OK, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length) if length > 0 else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path == "/api/digest":
            self._send_json(load_digest())
            return

        if path == "/api/llm-config":
            self._send_json(describe_config())
            return

        if path == "/api/health":
            reachable, detail = ping()
            cfg = describe_config()
            self._send_json(
                {
                    "llm_reachable": reachable,
                    "detail": detail,
                    "backend": cfg["backend"],
                    "base_url": cfg["base_url"],
                    "model": cfg["model"],
                    "applescript": applescript_available(),
                }
            )
            return

        if path == "/api/analytics":
            self._send_json(get_analytics())
            return

        if path == "/api/todos":
            self._send_json({"items": load_json_file(TODO_FILE, [])})
            return

        if path == "/api/review-queue":
            self._send_json({"items": get_or_init_review_queue()})
            return

        if path == "/api/audit/export":
            rows = []
            if AUDIT_FILE.exists():
                for line in AUDIT_FILE.read_text(encoding="utf-8").splitlines():
                    try:
                        rows.append(json.loads(line))
                    except Exception:
                        continue
            from io import StringIO

            out = StringIO()
            writer = csv.DictWriter(out, fieldnames=["ts", "action", "idx", "subject", "status", "detail"])
            writer.writeheader()
            for r in rows:
                writer.writerow(
                    {
                        "ts": r.get("ts", ""),
                        "action": r.get("action", ""),
                        "idx": r.get("idx", ""),
                        "subject": r.get("subject", ""),
                        "status": r.get("status", ""),
                        "detail": r.get("detail", ""),
                    }
                )
            self._send_text(out.getvalue(), ctype="text/csv; charset=utf-8")
            return

        if path == "/" or path == "":
            path = "/ui/"

        # Static serving for /ui and digest logs
        fs_path = (BASE / path.lstrip("/")).resolve()
        if path.startswith("/ui") and fs_path.exists() and fs_path.is_file() and str(fs_path).startswith(str(UI.resolve())):
            self._send_file(fs_path)
            return
        if path.startswith("/ui/") and fs_path.exists() and fs_path.is_file() and str(fs_path).startswith(str(UI.resolve())):
            self._send_file(fs_path)
            return
        if path == "/ui/":
            idx = UI / "index.html"
            self._send_file(idx)
            return

        if path.startswith("/logs/") and fs_path.exists() and fs_path.is_file() and str(fs_path).startswith(str(LOGS.resolve())):
            self._send_file(fs_path)
            return

        self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)

    def _send_file(self, path: Path):
        ctype = "text/plain; charset=utf-8"
        suffix = path.suffix.lower()
        if suffix == ".html":
            ctype = "text/html; charset=utf-8"
        elif suffix == ".css":
            ctype = "text/css; charset=utf-8"
        elif suffix == ".js":
            ctype = "application/javascript; charset=utf-8"
        elif suffix == ".json":
            ctype = "application/json; charset=utf-8"
        elif suffix == ".svg":
            ctype = "image/svg+xml"

        data = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        try:
            if path == "/api/chat":
                payload = self._read_json()
                user_messages = payload.get("messages", [])
                system_prompt = (
                    "You are Pix, a helpful pixel robot running locally. "
                    "Be concise, practical, and safety-conscious about calendar actions."
                )
                messages = [{"role": "system", "content": system_prompt}] + user_messages
                out = llm_chat(messages, temperature=0.3)
                self._send_json({"reply": out})
                return

            if path == "/api/refine-event-time":
                payload = self._read_json()
                data = refine_event_time(payload)
                self._send_json(data)
                return

            if path == "/api/importance-explain":
                payload = self._read_json()
                data = explain_importance(payload)
                self._send_json(data)
                return

            if path == "/api/calendar-conflicts":
                if not applescript_available():
                    self._send_json(
                        {"ok": False, "reason": "calendar integration requires a macOS host (osascript unavailable here)"},
                        status=HTTPStatus.NOT_IMPLEMENTED,
                    )
                    return
                payload = self._read_json()
                event = payload.get("event", {})
                conflicts = get_calendar_conflicts(event)
                self._send_json({"conflicts": conflicts})
                return

            if path == "/api/calendar-events":
                if not applescript_available():
                    self._send_json(
                        {"ok": False, "reason": "calendar integration requires a macOS host (osascript unavailable here); the UI falls back to .ics"},
                        status=HTTPStatus.NOT_IMPLEMENTED,
                    )
                    return
                payload = self._read_json()
                event = payload.get("event", payload)
                ok, reason = guardrail_check(event)
                if not ok:
                    append_jsonl(
                        AUDIT_FILE,
                        {
                            "ts": now_str(),
                            "action": "create_event",
                            "idx": payload.get("idx", ""),
                            "subject": payload.get("subject", event.get("title", "")),
                            "status": "blocked",
                            "detail": reason,
                        },
                    )
                    self._send_json({"ok": False, "reason": reason}, status=HTTPStatus.BAD_REQUEST)
                    return

                create_event_local(event)
                append_jsonl(
                    AUDIT_FILE,
                    {
                        "ts": now_str(),
                        "action": "create_event",
                        "idx": payload.get("idx", ""),
                        "subject": payload.get("subject", event.get("title", "")),
                        "status": "created",
                        "detail": "event created",
                    },
                )
                self._send_json({"ok": True, "status": "created"})
                return

            if path == "/api/review/batch":
                payload = self._read_json()
                action = payload.get("action", "")
                ids = payload.get("ids", [])
                queue = get_or_init_review_queue()

                changed = 0
                failures = []
                for row in queue:
                    if row.get("idx") not in ids:
                        continue
                    if action == "reject":
                        row["status"] = "rejected"
                        changed += 1
                        append_jsonl(
                            AUDIT_FILE,
                            {
                                "ts": now_str(),
                                "action": "batch_reject",
                                "idx": row.get("idx", ""),
                                "subject": row.get("subject", ""),
                                "status": "rejected",
                                "detail": "rejected by reviewer",
                            },
                        )
                        continue

                    if action == "approve":
                        ok, reason = guardrail_check(row.get("event", {}))
                        if not ok:
                            failures.append({"idx": row.get("idx"), "reason": reason})
                            continue
                        try:
                            create_event_local(row.get("event", {}))
                            row["status"] = "approved"
                            changed += 1
                            append_jsonl(
                                AUDIT_FILE,
                                {
                                    "ts": now_str(),
                                    "action": "batch_approve",
                                    "idx": row.get("idx", ""),
                                    "subject": row.get("subject", ""),
                                    "status": "approved",
                                    "detail": "event created",
                                },
                            )
                        except Exception as e:
                            failures.append({"idx": row.get("idx"), "reason": str(e)})

                save_json_file(REVIEW_FILE, queue)
                self._send_json({"changed": changed, "failures": failures, "items": queue})
                return

            if path == "/api/snooze":
                payload = self._read_json()
                hours = int(payload.get("hours", 24) or 24)
                until = (datetime.now() + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")
                row = {
                    "idx": payload.get("idx"),
                    "subject": payload.get("subject", ""),
                    "sender": payload.get("sender", ""),
                    "until": until,
                    "created_at": now_str(),
                }
                out = save_snooze(row)
                append_jsonl(
                    AUDIT_FILE,
                    {
                        "ts": now_str(),
                        "action": "snooze",
                        "idx": row.get("idx", ""),
                        "subject": row.get("subject", ""),
                        "status": "snoozed",
                        "detail": f"until {until}",
                    },
                )
                self._send_json({"ok": True, "until": until, **out})
                return

            if path == "/api/todos":
                payload = self._read_json()
                out = upsert_todos(payload.get("items", []))
                self._send_json({"ok": True, **out})
                return

            self._send_json({"error": "not found"}, status=HTTPStatus.NOT_FOUND)
        except subprocess.CalledProcessError as e:
            self._send_json({"error": "command failed", "detail": str(e)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)
        except requests.RequestException as e:
            self._send_json({"error": "model unavailable", "detail": str(e)}, status=HTTPStatus.BAD_GATEWAY)
        except Exception as e:
            self._send_json({"error": "internal error", "detail": str(e)}, status=HTTPStatus.INTERNAL_SERVER_ERROR)


def main():
    ensure_dirs()
    cfg = describe_config()
    print(
        f"LLM backend: {cfg['backend']}  base_url={cfg['base_url']}  "
        f"model={cfg['model']}  api_key_set={cfg['api_key_set']}"
    )
    print(
        "AppleScript calendar/mail: "
        + ("available" if applescript_available() else "unavailable (non-macOS host; calendar uses .ics fallback)")
    )
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Serving Email Agent local server on http://{HOST}:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
