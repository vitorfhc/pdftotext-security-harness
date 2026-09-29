#!/usr/bin/env python3
"""Send minimal ntfy alerts for new report-candidate conclusions."""

import json
import os
import signal
import sqlite3
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "workspace" / "research.db"
STATE = ROOT / "workspace" / ".notify-state.json"
SERVER = os.environ.get("NTFY_SERVER", "https://ntfy.sh").rstrip("/")
TOPIC = os.environ.get("NTFY_TOPIC", "").strip()
TOKEN = os.environ.get("NTFY_TOKEN", "").strip()
INCLUDE_SUMMARY = os.environ.get("NTFY_INCLUDE_SUMMARY", "1") == "1"
POLL_SECONDS = max(15, int(os.environ.get("NTFY_POLL_SECONDS", "60")))
STOP = False


def stop(*_):
    global STOP
    STOP = True


def connect():
    return sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=5)


def load_state():
    if not STATE.exists():
        return None
    return int(json.loads(STATE.read_text(encoding="utf-8"))["last_conclusion_id"])


def save_state(value):
    temporary = STATE.with_suffix(".new")
    temporary.write_text(json.dumps({"last_conclusion_id": value}) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(STATE)


def compact(text, limit=320):
    return " ".join((text or "").split())[:limit]


def send(conclusion_id, verdict, summary):
    if INCLUDE_SUMMARY:
        body = f"{compact(verdict, 100)}: {compact(summary)}"
    else:
        body = f"New report-candidate conclusion #{conclusion_id}. Review the local database."
    request = urllib.request.Request(
        f"{SERVER}/{TOPIC}",
        data=body.encode("utf-8"),
        method="POST",
        headers={
            "Title": "PDF research finding",
            "Priority": "high" if "RCE" in verdict.upper() else "default",
            "Tags": "warning",
        },
    )
    if TOKEN:
        request.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status >= 300:
            raise RuntimeError(f"ntfy returned HTTP {response.status}")


def main():
    if not TOPIC or TOPIC == "replace-with-a-long-random-topic":
        raise SystemExit("Set NTFY_TOPIC to a long private topic before starting the monitor.")
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    while not DB.exists() and not STOP:
        print("Waiting for workspace/research.db", flush=True)
        time.sleep(POLL_SECONDS)
    if STOP:
        return 0

    last = load_state()
    with connect() as db:
        maximum = db.execute("SELECT COALESCE(MAX(id), 0) FROM conclusions").fetchone()[0]
    if last is None:
        save_state(maximum)
        last = maximum
        print(f"Monitoring new conclusions after id {last}", flush=True)

    while not STOP:
        try:
            with connect() as db:
                rows = db.execute(
                    "SELECT id, verdict, summary FROM conclusions "
                    "WHERE id > ? AND report_candidate = 1 ORDER BY id",
                    (last,),
                ).fetchall()
                maximum = db.execute(
                    "SELECT COALESCE(MAX(id), ?) FROM conclusions", (last,)
                ).fetchone()[0]
            for conclusion_id, verdict, summary in rows:
                send(conclusion_id, verdict, summary)
                print(f"Sent notification for conclusion {conclusion_id}", flush=True)
            last = max(last, maximum)
            save_state(last)
        except (OSError, sqlite3.Error, RuntimeError, urllib.error.URLError) as exc:
            print(f"notification monitor: {exc}", file=sys.stderr, flush=True)
        for _ in range(POLL_SECONDS):
            if STOP:
                break
            time.sleep(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
