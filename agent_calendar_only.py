import json
import subprocess
from datetime import datetime
from pathlib import Path
import requests

LLAMA_URL = "http://127.0.0.1:8080/v1/chat/completions"
MODEL = "local"
TIMEZONE = "Europe/London"

CONF_THRESHOLD = 0.85  # 门控阈值：低于此值不自动写入日历

BASE = Path.home() / "ai_email_agent"
SCRIPT_EVENT = BASE / "scripts" / "create_event.applescript"
LOG_FILE = BASE / "logs" / "calendar_agent.log"


def log(msg: str) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(f"{datetime.now().isoformat(timespec='seconds')}  {msg}\n")


def to_macos_datestr(dt_str: str) -> str:
    """
    Input:  'YYYY-MM-DD HH:MM:SS'
    Output: '20 February 2026 15:00:00'  (AppleScript date parser friendly)
    """
    t = datetime.fromisoformat(dt_str)
    return t.strftime("%d %B %Y %H:%M:%S")


def call_llama(subject: str, body: str) -> dict:
    system = (
        "You must output EXACTLY one JSON object with keys: name, parameters. No extra text.\n"
        "Allowed names:\n"
        "1) create_calendar_event\n"
        "2) no_event\n\n"
        "For create_calendar_event, parameters MUST be:\n"
        "{title,start_datetime,end_datetime,timezone,location,notes,confidence,missing_fields}\n"
        "- start_datetime/end_datetime format: YYYY-MM-DD HH:MM:SS\n"
        f"- timezone MUST be {TIMEZONE} if local to Oxford\n"
        "- missing_fields is an array of strings\n"
        "- confidence is a float 0..1\n"
        "Rules:\n"
        "- Do NOT guess. If date/time is missing or ambiguous, output no_event with reason.\n"
        "- If any required field is missing, put its name in missing_fields and still output create_calendar_event only if confident.\n"
    )

    user = f"Subject: {subject}\nBody: {body}"

    payload = {
        "model": MODEL,
        "temperature": 0.1,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }

    r = requests.post(LLAMA_URL, json=payload, timeout=120)
    r.raise_for_status()
    content = r.json()["choices"][0]["message"]["content"].strip()
    return json.loads(content)


def create_event(title: str, start_dt: str, end_dt: str, location: str, notes: str) -> None:
    start_str = to_macos_datestr(start_dt)
    end_str = to_macos_datestr(end_dt)

    cmd = [
        "osascript",
        str(SCRIPT_EVENT),
        title,
        start_str,
        end_str,
        location,
        notes,
    ]
    subprocess.run(cmd, check=True)


def gate_and_execute(tool_call: dict) -> str:
    name = tool_call.get("name", "")
    params = tool_call.get("parameters", {}) or {}

        # --- normalize types from LLM (robust against stringified JSON) ---
    # confidence: allow "1" -> 1.0
    if "confidence" in params and isinstance(params["confidence"], str):
        try:
            params["confidence"] = float(params["confidence"].strip())
        except Exception:
            pass

    # missing_fields: allow "[]" -> []
    mf = params.get("missing_fields", [])
    if isinstance(mf, str):
        s = mf.strip()
        if s in ("", "[]", "null", "None"):
            mf = []
        else:
            try:
                mf = json.loads(s)
            except Exception:
                mf = [x.strip() for x in s.split(",") if x.strip()]
    if mf is None:
        mf = []
    if not isinstance(mf, list):
        mf = [str(mf)]
    params["missing_fields"] = mf


    if name == "no_event":
        reason = params.get("reason", "unspecified")
        return f"No event created: {reason}"

    if name != "create_calendar_event":
        return f"Rejected: unexpected name={name}"

    # Required keys
    required = ["title", "start_datetime", "end_datetime", "timezone", "confidence", "missing_fields"]
    miss = [k for k in required if k not in params]
    if miss:
        return f"Rejected: missing required keys {miss}"

    # Hard constraints
    if params["timezone"] != TIMEZONE:
        return f"Rejected: timezone={params['timezone']} (expected {TIMEZONE})"

    if params["missing_fields"]:
        return f"Rejected: missing_fields={params['missing_fields']}"

    conf = float(params["confidence"])
    if conf < CONF_THRESHOLD:
        return f"Rejected: confidence={conf:.2f} < {CONF_THRESHOLD}"

    # Parse and sanity-check time order
    start_dt = datetime.fromisoformat(params["start_datetime"])
    end_dt = datetime.fromisoformat(params["end_datetime"])
    if end_dt <= start_dt:
        return "Rejected: end_datetime must be after start_datetime"

    # Execute
    create_event(
        title=params["title"],
        start_dt=params["start_datetime"],
        end_dt=params["end_datetime"],
        location=params.get("location", ""),
        notes=params.get("notes", ""),
    )
    return "OK: event created in Calendar 'AI Drafts'"


def main():
    # Demo email (你可以改成真实邮件内容)
    subject = "Group meeting"
    body = "Let us meet on 20 Feb 2026 15:00-16:00 in Oxford. Agenda: project update. Please bring updated slides."

    tool_call = call_llama(subject, body)
    log(f"LLM output: {tool_call}")

    result = gate_and_execute(tool_call)
    log(f"Result: {result}")
    print(result)


if __name__ == "__main__":
    main()

