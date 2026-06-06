#!/usr/bin/env python3
"""Preflight check for the Local Email Agent.

Confirms everything needed for a real email feed is in place:
  - local LLM (vMLX / mlx_lm.server) reachable
  - required AppleScript files present
  - macOS host with osascript (for the Mail/Calendar worker)
  - Mail.app accounts visible (also triggers the Automation permission prompt)

Run:  python3 check_setup.py
"""

import shutil
import subprocess
import sys
from pathlib import Path

from llm_client import describe_config, ping

BASE = Path(__file__).resolve().parent
SCRIPTS = BASE / "scripts"
REQUIRED_SCRIPTS = [
    "fetch_unread_mail.applescript",
    "mark_read_by_id.applescript",
    "create_event.applescript",
]


def check(label: str, ok: bool, detail: str = "") -> bool:
    mark = "OK  " if ok else "FAIL"
    print(f"[{mark}] {label}" + (f"  — {detail}" if detail else ""))
    return ok


def main() -> int:
    print("Local Email Agent — setup check\n")
    all_ok = True

    cfg = describe_config()
    print(f"LLM backend: {cfg['backend']}  base_url={cfg['base_url']}  model={cfg['model']}\n")

    # 1. Local LLM reachable
    reachable, detail = ping()
    all_ok &= check("Local LLM reachable", reachable, detail)
    if not reachable:
        print("       -> Start vMLX / mlx_lm.server on the base_url above, or set LLM_BASE_URL.")

    # 2. Required scripts present
    for s in REQUIRED_SCRIPTS:
        all_ok &= check(f"Script present: {s}", (SCRIPTS / s).exists())

    # 3. macOS + osascript (needed only for the Mail/Calendar worker)
    is_mac = sys.platform == "darwin"
    has_osa = shutil.which("osascript") is not None
    mac_ok = is_mac and has_osa
    check(
        "macOS host with osascript",
        mac_ok,
        "" if mac_ok else "non-macOS: UI + LLM endpoints work, but no Mail/Calendar feed",
    )

    # 4. Mail.app reachable (mac only). Also surfaces the Automation permission prompt.
    if mac_ok:
        try:
            out = subprocess.run(
                ["osascript", "-e", 'tell application "Mail" to get name of every account'],
                capture_output=True,
                text=True,
                timeout=20,
            )
            accounts = out.stdout.strip()
            ok = out.returncode == 0 and bool(accounts)
            all_ok &= check("Mail.app accounts visible", ok, accounts or out.stderr.strip())
            if not ok:
                print(
                    "       -> System Settings > Privacy & Security > Automation: "
                    "allow your terminal to control Mail."
                )
        except Exception as e:
            all_ok &= check("Mail.app accounts visible", False, str(e))

    print()
    if all_ok:
        print("All checks passed.")
        print("Next:  python3 agent_mail_calendar.py   (populate digest)")
        print("Then:  python3 api_server.py            (serve UI)  ->  http://127.0.0.1:8000/ui/")
        return 0
    print("Some checks failed — fix the items above before running the worker.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
