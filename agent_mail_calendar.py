import json
import os
import subprocess
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional
from zoneinfo import ZoneInfo

import requests

# =========================
# Config
# =========================
LLAMA_URL = "http://127.0.0.1:8080/v1/chat/completions"
MODEL = "local"

TIMEZONE_TARGET = "Europe/London"
CONF_THRESHOLD = 0.85

# Digest email
SEND_DIGEST_EMAIL = True
DIGEST_TO = "wolf6966@ox.ac.uk"

# Limits
MAX_UNREAD = 10
MAX_BODY_CHARS = 5000

# Paths
REPO_BASE = Path(__file__).resolve().parent
DEFAULT_HOME_BASE = Path.home() / "ai_email_agent"
ENV_BASE = os.getenv("AI_EMAIL_AGENT_BASE", "").strip()

if ENV_BASE:
    BASE = Path(ENV_BASE).expanduser()
elif (DEFAULT_HOME_BASE / "scripts").exists():
    BASE = DEFAULT_HOME_BASE
else:
    BASE = REPO_BASE

S_SEND = BASE / "scripts" / "send_digest.applescript"
S_FETCH = BASE / "scripts" / "fetch_unread_mail.applescript"
S_MARKREAD = BASE / "scripts" / "mark_read_by_id.applescript"
S_EVENT = BASE / "scripts" / "create_event.applescript"

STATE = BASE / "state"
LOGS = BASE / "logs"
PROCESSED_FILE = STATE / "processed_ids.json"
DIGEST_FILE = LOGS / "latest_digest.txt"
DIGEST_JSON_FILE = LOGS / "latest_digest.json"
HISTORY_FILE = LOGS / "digest_history.jsonl"
LOG_FILE = LOGS / "agent.log"

# Request timeouts: (connect_timeout, read_timeout)
HTTP_TIMEOUT = (10, 180)


# =========================
# Logging + progress helpers
# =========================
def now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def log(msg: str) -> None:
    LOGS.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"{now_str()}  {msg}\n")


def info(msg: str) -> None:
    print(f"[{now_str()}] {msg}", flush=True)
    log(msg)


class Heartbeat:
    """Print periodic heartbeat while a long operation runs."""

    def __init__(self, label: str, interval_sec: int = 5):
        self.label = label
        self.interval = interval_sec
        self._stop = threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        tick = 0
        while not self._stop.wait(self.interval):
            tick += 1
            info(f"{self.label} ... still waiting ({tick * self.interval}s)")

    def __enter__(self):
        self._t.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        self._stop.set()
        try:
            self._t.join(timeout=0.2)
        except Exception:
            pass


# =========================
# State
# =========================
def load_processed() -> set[str]:
    STATE.mkdir(parents=True, exist_ok=True)
    if not PROCESSED_FILE.exists():
        return set()
    try:
        data = json.loads(PROCESSED_FILE.read_text(encoding="utf-8"))
        return set(data) if isinstance(data, list) else set()
    except Exception:
        return set()


def save_processed(s: set[str]) -> None:
    PROCESSED_FILE.write_text(
        json.dumps(sorted(list(s)), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


# =========================
# AppleScript wrappers
# =========================
def run_osascript_capture(script_path: Path, *args: str) -> str:
    cmd = ["osascript", str(script_path), *args]
    out = subprocess.check_output(cmd)
    return out.decode("utf-8", errors="replace").strip()


def send_digest_email(to_email: str, subject_line: str, body_text: str) -> None:
    run_osascript_capture(S_SEND, to_email, subject_line, body_text)


def fetch_unread(max_n: int) -> list[dict]:
    raw = run_osascript_capture(S_FETCH, str(max_n))
    return json.loads(raw)


def mark_read(message_id: str) -> None:
    run_osascript_capture(S_MARKREAD, message_id)


def to_macos_datestr(dt_str: str) -> str:
    dt = datetime.fromisoformat(dt_str)
    return dt.strftime("%d %B %Y %H:%M:%S")


def create_event_calendar(title: str, start_dt: str, end_dt: str, location: str, notes: str) -> None:
    start_str = to_macos_datestr(start_dt)
    end_str = to_macos_datestr(end_dt)
    run_osascript_capture(S_EVENT, title, start_str, end_str, location, notes)


# =========================
# JSON robust parsing + extraction
# =========================
def extract_first_json_object(s: str) -> Optional[str]:
    """Extract first top-level JSON object {...} from a string."""
    if not s:
        return None
    start = s.find("{")
    if start == -1:
        return None

    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(s)):
        ch = s[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return s[start : i + 1]
    return None


def safe_json_loads(raw: str) -> dict:
    """
    Robust JSON parsing for LLM outputs.
    1) Try direct json.loads
    2) Strip code fences
    3) Extract first {...} object and parse
    """
    if raw is None:
        raise ValueError("Empty LLM output")

    s = raw.strip()

    if s.startswith("```"):
        s = s.replace("```json", "").replace("```", "").strip()

    try:
        return json.loads(s)
    except Exception:
        pass

    obj = extract_first_json_object(s)
    if obj:
        return json.loads(obj)

    raise ValueError("Could not parse JSON from LLM output")


# =========================
# Timezone conversions
# =========================
def tz_map(tz: str) -> Optional[str]:
    t = (tz or "").strip()
    if t == "Europe/London":
        return "Europe/London"
    if t in ("UTC", "GMT"):
        return "UTC"
    if t in ("Europe/Berlin", "CET", "CEST"):
        return "Europe/Berlin"
    if t in ("Europe/Paris",):
        return "Europe/Paris"
    return None


def convert_event_to_london(ev: dict) -> dict:
    start = (ev.get("start_datetime") or "").strip()
    end = (ev.get("end_datetime") or "").strip()
    tz = (ev.get("timezone") or "").strip()
    src_zone = tz_map(tz)
    if not start or not end or not src_zone:
        return ev

    try:
        dt_start = datetime.fromisoformat(start).replace(tzinfo=ZoneInfo(src_zone))
        dt_end = datetime.fromisoformat(end).replace(tzinfo=ZoneInfo(src_zone))
        dt_start_ldn = dt_start.astimezone(ZoneInfo(TIMEZONE_TARGET))
        dt_end_ldn = dt_end.astimezone(ZoneInfo(TIMEZONE_TARGET))
        ev["start_datetime"] = dt_start_ldn.strftime("%Y-%m-%d %H:%M:%S")
        ev["end_datetime"] = dt_end_ldn.strftime("%Y-%m-%d %H:%M:%S")
        ev["timezone"] = TIMEZONE_TARGET
    except Exception:
        pass
    return ev


# =========================
# Normalization
# =========================
def normalize_types(params: dict) -> dict:
    if "importance" in params and isinstance(params["importance"], str):
        try:
            params["importance"] = int(float(params["importance"].strip()))
        except Exception:
            pass

    if "calendar_candidate" in params and isinstance(params["calendar_candidate"], str):
        s = params["calendar_candidate"].strip().lower()
        params["calendar_candidate"] = s in ("true", "1", "yes")

    ai = params.get("action_items", [])
    if isinstance(ai, str):
        s = ai.strip()
        try:
            ai2 = json.loads(s)
            ai = ai2 if isinstance(ai2, list) else [s]
        except Exception:
            items = [x.strip() for x in s.split("\n") if x.strip()]
            if not items:
                items = [x.strip() for x in s.split(",") if x.strip()]
            ai = items
    if ai is None:
        ai = []
    if not isinstance(ai, list):
        ai = [str(ai)]
    params["action_items"] = ai

    ev = params.get("event", {}) or {}
    if isinstance(ev, str):
        try:
            ev = json.loads(ev)
        except Exception:
            ev = {}
    if not isinstance(ev, dict):
        ev = {}

    if "confidence" in ev and isinstance(ev["confidence"], str):
        try:
            ev["confidence"] = float(ev["confidence"].strip())
        except Exception:
            pass

    mf = ev.get("missing_fields", [])
    if isinstance(mf, str):
        s = mf.strip()
        if s in ("", "[]", "null", "None"):
            mf = []
        else:
            try:
                mf2 = json.loads(s)
                mf = mf2 if isinstance(mf2, list) else [s]
            except Exception:
                mf = [x.strip() for x in s.split(",") if x.strip()]
    if mf is None:
        mf = []
    if not isinstance(mf, list):
        mf = [str(mf)]
    ev["missing_fields"] = mf

    for k in ("title", "start_datetime", "end_datetime", "timezone", "location", "notes"):
        if k in ev and ev[k] is None:
            ev[k] = ""
        if k not in ev:
            ev[k] = ""

    params["event"] = ev
    return params


# =========================
# Digest
# =========================
def build_digest(entries: list[dict], stats: dict) -> str:
    lines = []
    lines.append(f"AI Email Digest  ({now_str()}  {TIMEZONE_TARGET})")
    lines.append("=" * 72)
    lines.append(
        f"Processed: {stats['processed']} | Created events: {stats['created']} | "
        f"Not created: {stats['not_created']} | Failed: {stats['failed']}"
    )

    if not entries:
        lines.append("\nNo new unread emails processed.")
        return "\n".join(lines)

    entries = sorted(entries, key=lambda x: x.get("importance", 0), reverse=True)

    for i, e in enumerate(entries, 1):
        lines.append(f"\n[{i}] Importance: {e.get('importance')} | {e.get('sender')} | {e.get('subject')}")
        lines.append(f"    Date: {e.get('date')}")
        lines.append(f"    Summary: {e.get('summary')}")
        if e.get("action_items"):
            lines.append("    Action items:")
            for a in e["action_items"]:
                lines.append(f"      - {a}")
        lines.append(f"    Calendar: {e.get('calendar_result')}")
        if e.get("event_preview"):
            lines.append(f"    Event preview: {e['event_preview']}")
    return "\n".join(lines)


def extract_event_from_preview(event_preview: str, fallback_title: str, fallback_notes: str) -> Optional[dict]:
    s = (event_preview or "").strip()
    if not s:
        return None

    if " @ " in s and "–" in s:
        try:
            rng, location = s.split(" @ ", 1)
            start, end = [x.strip() for x in rng.split("–", 1)]
            return {
                "title": fallback_title or "Email Event",
                "start_datetime": start,
                "end_datetime": end,
                "location": location.strip(),
                "notes": fallback_notes or "",
            }
        except Exception:
            return None

    if s.startswith("title="):
        parts = {}
        for kv in s.split(","):
            if "=" not in kv:
                continue
            k, v = kv.split("=", 1)
            parts[k.strip()] = v.strip()
        if parts.get("title") and parts.get("start") and parts.get("end"):
            return {
                "title": parts.get("title", ""),
                "start_datetime": parts.get("start", ""),
                "end_datetime": parts.get("end", ""),
                "location": "",
                "notes": fallback_notes or "",
            }
    return None


def build_digest_json(entries: list[dict], stats: dict) -> dict:
    items = sorted(entries, key=lambda x: x.get("importance", 0), reverse=True)
    out = []
    for idx, e in enumerate(items, 1):
        event = extract_event_from_preview(
            e.get("event_preview", ""),
            e.get("subject", ""),
            e.get("summary", ""),
        )
        out.append(
            {
                "idx": idx,
                "importance": int(e.get("importance", 0) or 0),
                "sender": e.get("sender", ""),
                "subject": e.get("subject", ""),
                "date": e.get("date", ""),
                "summary": e.get("summary", ""),
                "action_items": e.get("action_items", []),
                "calendar_result": e.get("calendar_result", ""),
                "event_preview": e.get("event_preview", ""),
                "event": event,
                "message_id": e.get("message_id", ""),
                "body_preview": e.get("body_preview", ""),
            }
        )

    return {
        "meta": {
            "generated_at": now_str(),
            "timezone": TIMEZONE_TARGET,
            "source": "agent_mail_calendar.py",
        },
        "stats": {
            "processed": int(stats.get("processed", 0) or 0),
            "created": int(stats.get("created", 0) or 0),
            "not_created": int(stats.get("not_created", 0) or 0),
            "failed": int(stats.get("failed", 0) or 0),
        },
        "items": out,
    }


def append_digest_history(digest_json: dict) -> None:
    row = {
        "ts": datetime.now().isoformat(timespec="seconds"),
        "stats": digest_json.get("stats", {}),
        "items": digest_json.get("items", []),
    }
    with HISTORY_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


# =========================
# LLM prompts
# =========================
ANALYZE_SYSTEM_PROMPT = f"""
You must output EXACTLY ONE line of valid JSON. No extra text. No markdown fences.

Importance rules (hard):
- If the email is about manuscript decision (accepted/rejected/major revision/minor revision/decision letter), set importance=3.
- If the email asks for proofs, copyright/license, final files, or APC/payment for a paper, set importance=3.

Output schema:
{{
  "name":"analyze_email",
  "parameters":{{
    "message_id":"<string>",
    "importance":<integer 0..3>,
    "summary":"<string>",
    "action_items":["<string>", ...],
    "calendar_candidate":<true|false>,
    "event":{{
      "title":"<string>",
      "start_datetime":"YYYY-MM-DD HH:MM:SS",
      "end_datetime":"YYYY-MM-DD HH:MM:SS",
      "timezone":"{TIMEZONE_TARGET}",
      "location":"<string>",
      "notes":"<string>",
      "confidence":<number 0..1>,
      "missing_fields":["<string>", ...]
    }}
  }}
}}

Strict JSON constraints (MUST FOLLOW):
- Output must be ONE single line (no newline characters).
- Do not include any double quote characters inside any string value. If needed, replace with single quotes or remove.
- Do NOT paste raw email text. Summarize in your own words.
- Keep summary and notes short (<= 200 characters each).
- action_items: at most 5 items, each <= 120 characters.
- Do NOT guess datetimes. If ambiguous or missing, leave as empty string "" and put the key name into missing_fields.
- Use timezone "{TIMEZONE_TARGET}" for Oxford/London. If email uses CET/CEST/UTC, convert to "{TIMEZONE_TARGET}" if clear.
""".strip()

REPAIR_SYSTEM_PROMPT = """
You are a strict JSON repair tool.

Task:
- You will receive a broken JSON-like string that SHOULD match a given schema.
- Output MUST be EXACTLY ONE line of valid JSON and NOTHING else (no markdown, no explanations).
- Preserve the original meaning as much as possible.
- Apply strict constraints:
  - One line only (no newline characters).
  - Do not include any double quote characters inside any string value; replace with single quotes or remove.
  - Ensure all required keys exist; if missing, add them with safe defaults:
    - importance: 0
    - summary: ""
    - action_items: []
    - calendar_candidate: false
    - event fields: empty strings, confidence 0.0, missing_fields []
""".strip()


# =========================
# LLM calls
# =========================
def llm_chat(messages: list[dict], temperature: float = 0.1) -> str:
    payload = {"model": MODEL, "temperature": temperature, "messages": messages}
    r = requests.post(LLAMA_URL, json=payload, timeout=HTTP_TIMEOUT)
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def repair_json_with_llm(bad_text: str, error_msg: str) -> dict:
    bad_text = (bad_text or "")[:8000]
    user = (
        "Fix the following broken JSON to valid JSON.\n"
        f"Parser error: {error_msg}\n"
        "Broken content:\n"
        f"{bad_text}"
    )
    with Heartbeat("LLM repairing JSON", interval_sec=5):
        out = llm_chat(
            [
                {"role": "system", "content": REPAIR_SYSTEM_PROMPT},
                {"role": "user", "content": user},
            ],
            temperature=0.0,
        )
    return safe_json_loads(out)


def call_llm_analyze(email: dict) -> dict:
    body = (email.get("body") or "").replace("\x00", "")
    if len(body) > MAX_BODY_CHARS:
        body = body[:MAX_BODY_CHARS] + "\n[TRUNCATED]"

    user = (
        f"message_id: {email.get('id','')}\n"
        f"From: {email.get('sender','')}\n"
        f"Date: {email.get('date','')}\n"
        f"Subject: {email.get('subject','')}\n"
        f"Body:\n{body}"
    )

    last_err = None
    last_content = ""

    with Heartbeat("LLM analyzing email", interval_sec=5):
        for attempt in range(2):
            try:
                content = llm_chat(
                    [
                        {"role": "system", "content": ANALYZE_SYSTEM_PROMPT},
                        {"role": "user", "content": user},
                    ],
                    temperature=0.1,
                )
                last_content = content
                return safe_json_loads(content)
            except Exception as e:
                last_err = e
                info(f"LLM analyze call/parse failed (attempt {attempt+1}/2): {e}")
                log(f"LLM analyze raw (trunc 2000c): {str(last_content)[:2000]}")
                time.sleep(1)

    info("Entering JSON repair loop")
    repaired = repair_json_with_llm(last_content, str(last_err))
    return repaired


# =========================
# Calendar gating
# =========================
def should_create_event(params: dict) -> tuple[bool, str]:
    if not params.get("calendar_candidate", False):
        return False, "calendar_candidate=false"

    ev = params.get("event", {}) or {}

    for k in ("title", "start_datetime", "end_datetime", "timezone", "confidence", "missing_fields"):
        if k not in ev:
            return False, f"missing event key: {k}"

    if ev.get("timezone") != TIMEZONE_TARGET:
        return False, f"timezone={ev.get('timezone')}"

    if ev.get("missing_fields"):
        return False, f"missing_fields={ev.get('missing_fields')}"

    try:
        conf = float(ev.get("confidence", 0.0))
    except Exception:
        conf = 0.0
    if conf < CONF_THRESHOLD:
        return False, f"confidence={conf:.2f} < {CONF_THRESHOLD}"

    try:
        s = datetime.fromisoformat(ev["start_datetime"])
        e = datetime.fromisoformat(ev["end_datetime"])
        if e <= s:
            return False, "end_datetime <= start_datetime"
    except Exception:
        return False, "datetime parse failed"

    return True, "ok"


# =========================
# Main
# =========================
def main():
    info("Agent start")

    # Basic checks (fail fast)
    for p in (S_FETCH, S_MARKREAD, S_EVENT, S_SEND):
        if not p.exists():
            raise FileNotFoundError(f"Missing script: {p}")

    STATE.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)

    processed = load_processed()

    mails = fetch_unread(MAX_UNREAD)
    if not isinstance(mails, list):
        raise RuntimeError("Mail fetch did not return a list")

    mails = [m for m in mails if m.get("id") and m["id"] not in processed]
    total = len(mails)

    info(f"Unread fetched (unprocessed): {total} (max={MAX_UNREAD})")

    # If no new emails, still send a digest email (useful for scheduled runs)
    if total == 0:
        empty_stats = {"processed": 0, "created": 0, "not_created": 0, "failed": 0}
        digest = build_digest([], {"processed": 0, "created": 0, "not_created": 0, "failed": 0})
        digest_json = build_digest_json([], empty_stats)
        DIGEST_FILE.write_text(digest, encoding="utf-8")
        DIGEST_JSON_FILE.write_text(
            json.dumps(
                digest_json,
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        append_digest_history(digest_json)

        if SEND_DIGEST_EMAIL:
            info("Stage: send digest email")
            subject = f"AI Email Digest ({now_str()} {TIMEZONE_TARGET})"
            try:
                send_digest_email(DIGEST_TO, subject, digest)
                info(f"Digest emailed to: {DIGEST_TO}")
            except Exception as e:
                info(f"Digest email FAILED: {e}")
                log(f"Digest email FAILED: {e}")

        print(digest)
        info("Agent done")
        return

    entries = []
    stats = {"processed": 0, "created": 0, "not_created": 0, "failed": 0}

    for idx, m in enumerate(mails, 1):
        mid = m.get("id", "")
        subj = (m.get("subject", "") or "").strip()
        sndr = (m.get("sender", "") or "").strip()

        info(f"({idx}/{total}) Processing: {subj}  |  {sndr}")

        try:
            info("Stage: LLM analyze")
            tool = call_llm_analyze(m)
            log(f"LLM tool raw parsed: {tool}")

            if tool.get("name") != "analyze_email":
                info(f"Stage: skip (unexpected tool name={tool.get('name')})")
                processed.add(mid)
                save_processed(processed)
                stats["processed"] += 1
                continue

            params = tool.get("parameters", {}) or {}
            params = normalize_types(params)

            params["event"] = convert_event_to_london(params.get("event", {}) or {})

            info("Stage: calendar decision")
            ok, reason = should_create_event(params)

            calendar_result = "none"
            event_preview = ""

            if ok:
                ev = params["event"]
                info("Stage: create calendar event")
                try:
                    create_event_calendar(
                        title=ev.get("title") or subj or "Event",
                        start_dt=ev["start_datetime"],
                        end_dt=ev["end_datetime"],
                        location=ev.get("location", ""),
                        notes=ev.get("notes", ""),
                    )
                    calendar_result = "CREATED in AI Drafts"
                    event_preview = f"{ev['start_datetime']}–{ev['end_datetime']} @ {ev.get('location','')}"
                    stats["created"] += 1
                    info("Calendar: CREATED")
                except Exception as e:
                    calendar_result = f"FAILED to create event: {e}"
                    stats["failed"] += 1
                    info(f"Calendar: FAILED ({e})")
            else:
                if params.get("calendar_candidate", False):
                    calendar_result = f"NOT created ({reason})"
                    stats["not_created"] += 1
                    ev = params.get("event", {}) or {}
                    if ev.get("start_datetime") or ev.get("end_datetime") or ev.get("title"):
                        event_preview = (
                            f"title={ev.get('title','')}, start={ev.get('start_datetime','')}, "
                            f"end={ev.get('end_datetime','')}, tz={ev.get('timezone','')}"
                        )
                    info(f"Calendar: NOT created ({reason})")
                else:
                    calendar_result = "not applicable"
                    info("Calendar: not applicable")

            entry = {
                "importance": params.get("importance", 0),
                "sender": sndr,
                "subject": subj,
                "date": m.get("date", ""),
                "summary": params.get("summary", ""),
                "action_items": params.get("action_items", []),
                "calendar_result": calendar_result,
                "event_preview": event_preview,
                "message_id": mid,
                "body_preview": (m.get("body", "") or "")[:500],
            }
            entries.append(entry)

            processed.add(mid)
            save_processed(processed)
            stats["processed"] += 1

        except KeyboardInterrupt:
            info("KeyboardInterrupt: saving state then exiting")
            save_processed(processed)
            raise

        except Exception as e:
            info(f"ERROR processing email: {e}")
            log(f"Error processing {mid}: {e}")
            processed.add(mid)
            save_processed(processed)
            stats["processed"] += 1
            stats["failed"] += 1

        finally:
            info("Stage: mark email as read")
            try:
                mark_read(mid)
            except Exception as e:
                info(f"Mark read failed: {e}")
                log(f"Mark read failed for {mid}: {e}")

    info("Stage: build digest")
    digest = build_digest(entries, stats)
    digest_json = build_digest_json(entries, stats)
    DIGEST_FILE.write_text(digest, encoding="utf-8")
    DIGEST_JSON_FILE.write_text(
        json.dumps(digest_json, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    append_digest_history(digest_json)
    info(f"Digest saved: {DIGEST_FILE}")

    if SEND_DIGEST_EMAIL:
        info("Stage: send digest email")
        subject = f"AI Email Digest ({now_str()} {TIMEZONE_TARGET})"
        try:
            send_digest_email(DIGEST_TO, subject, digest)
            info(f"Digest emailed to: {DIGEST_TO}")
        except Exception as e:
            info(f"Digest email FAILED: {e}")
            log(f"Digest email FAILED: {e}")

    print(digest)
    info("Agent done")


if __name__ == "__main__":
    main()
