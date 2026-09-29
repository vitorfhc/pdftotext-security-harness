#!/usr/bin/env python3
"""Local SQLite research recorder. No network or third-party dependencies."""

import argparse
import json
import os
import shlex
import sqlite3
import sys
from pathlib import Path


WORKSPACE = Path(__file__).resolve().parents[1]
DB_PATH = WORKSPACE / "research.db"
SCHEMA_PATH = WORKSPACE / "schema.sql"
MAX_INPUT_BYTES = 16 * 1024
MAX_HOOK_BYTES = 1024 * 1024


def connect(require_existing=True):
    if require_existing and not DB_PATH.is_file():
        raise RuntimeError(f"missing database: {DB_PATH}; run init first")
    db = sqlite3.connect(DB_PATH, timeout=5)
    db.execute("PRAGMA busy_timeout = 5000")
    db.execute("PRAGMA journal_mode = WAL")
    db.execute("PRAGMA foreign_keys = ON")
    return db


def bounded_text(value, field, limit, required=True):
    if value is None and not required:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{field} must be a string")
    value = value.strip()
    if required and not value:
        raise ValueError(f"{field} must not be empty")
    if len(value) > limit:
        raise ValueError(f"{field} exceeds {limit} characters")
    return value


def bounded_list(value, field):
    if value is None:
        return []
    if not isinstance(value, list) or len(value) > 20:
        raise ValueError(f"{field} must be a list of at most 20 strings")
    return [bounded_text(item, field, 160) for item in value]


def read_payload():
    raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        raise ValueError("input exceeds 16 KiB")
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        raise ValueError("input must be a JSON object")
    return payload


def hook_event():
    raw = sys.stdin.buffer.read(MAX_HOOK_BYTES + 1)
    if len(raw) > MAX_HOOK_BYTES:
        raise ValueError("hook event exceeds 1 MiB; omitted")
    event = json.loads(raw)
    if not isinstance(event, dict):
        raise ValueError("hook event must be a JSON object")

    def field(name, limit=256):
        value = event.get(name)
        if value is None:
            return None
        return bounded_text(value, name, limit, required=False)

    event_type = bounded_text(event.get("hook_event_name"), "hook_event_name", 64)
    session_id = field("session_id")
    turn_id = field("turn_id")
    tool_use_id = field("tool_use_id")
    agent_id = field("agent_id")
    tool_name = field("tool_name")
    if event_type in ("PreToolUse", "PostToolUse"):
        outcome = "planned" if event_type == "PreToolUse" else "returned"
    else:
        outcome = None
    input_bytes = (
        len(json.dumps(event["tool_input"], ensure_ascii=False).encode("utf-8"))
        if "tool_input" in event else None
    )
    response_bytes = (
        len(json.dumps(event["tool_response"], ensure_ascii=False).encode("utf-8"))
        if "tool_response" in event else None
    )
    identity = tool_use_id or agent_id
    dedupe_key = (
        f"{session_id}:{turn_id}:{event_type}:{identity}"
        if identity is not None else None
    )
    with connect() as db:
        db.execute(
            "INSERT INTO telemetry_events "
            "(event_type, session_id, turn_id, tool_use_id, agent_id, tool_name, "
            "outcome, input_bytes, response_bytes, dedupe_key) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(dedupe_key) DO NOTHING",
            (event_type, session_id, turn_id, tool_use_id, agent_id, tool_name,
             outcome, input_bytes, response_bytes, dedupe_key),
        )
    print("{}")


def hooks_config():
    command = f"{shlex.quote(sys.executable)} {shlex.quote(str(Path(__file__).resolve()))} hook-event"
    names = (
        "SessionStart", "SessionEnd", "PreToolUse", "PostToolUse",
        "PreCompact", "PostCompact", "SubagentStart", "SubagentStop",
        "Stop", "Interrupt",
    )
    config = {"hooks": {
        name: [{"hooks": [{"type": "command", "command": command, "timeout": 5}]}]
        for name in names
    }}
    print(json.dumps(config, indent=2))


def initialize():
    os.umask(0o077)
    with connect(require_existing=False) as db:
        db.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    DB_PATH.chmod(0o600)
    print("research database ready")


def change_vector():
    payload = read_payload()
    allowed = {
        "hypothesis_id", "decision", "evidence_refs", "reason", "next_action",
        "alternatives_considered", "session_id", "idempotency_key",
    }
    unknown = set(payload) - allowed
    if unknown:
        raise ValueError(f"unknown fields: {', '.join(sorted(unknown))}")
    hypothesis_id = payload.get("hypothesis_id")
    if hypothesis_id is not None and (
        isinstance(hypothesis_id, bool) or not isinstance(hypothesis_id, int)
        or hypothesis_id < 1
    ):
        raise ValueError("hypothesis_id must be a positive integer")
    record = (
        hypothesis_id,
        bounded_text(payload.get("decision"), "decision", 200),
        json.dumps(bounded_list(payload.get("evidence_refs"), "evidence_refs")),
        bounded_text(payload.get("reason"), "reason", 500),
        bounded_text(payload.get("next_action"), "next_action", 200),
        json.dumps(bounded_list(payload.get("alternatives_considered"), "alternatives_considered")),
        bounded_text(payload.get("session_id"), "session_id", 128, required=False),
        bounded_text(payload.get("idempotency_key"), "idempotency_key", 128, required=False),
    )
    with connect() as db:
        cursor = db.execute(
            "INSERT INTO change_vectors "
            "(hypothesis_id, decision, evidence_refs_json, reason, next_action, "
            "alternatives_json, session_id, idempotency_key) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(idempotency_key) DO NOTHING", record
        )
        if cursor.rowcount == 0:
            existing = db.execute(
                "SELECT id, hypothesis_id, decision, evidence_refs_json, reason, "
                "next_action, alternatives_json, session_id, idempotency_key "
                "FROM change_vectors WHERE idempotency_key = ?", (record[-1],)
            ).fetchone()
            if existing is None or tuple(existing[1:]) != record:
                raise ValueError("idempotency_key already belongs to a different record")
            record_id = existing[0]
        else:
            record_id = cursor.lastrowid
    print(record_id)


def status():
    with connect() as db:
        integrity = db.execute("PRAGMA quick_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"database integrity check failed: {integrity}")
        for table in ("hypotheses", "experiments", "observations", "conclusions", "change_vectors", "telemetry_events"):
            count = db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
            print(f"{table}: {count}")
        for row in db.execute(
            "SELECT id, decision FROM change_vectors ORDER BY id DESC LIMIT 5"
        ):
            print(f"change_vector {row[0]}: {row[1]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "change-vector", "status", "hook-event", "hooks-config"))
    args = parser.parse_args()
    try:
        {"init": initialize, "change-vector": change_vector, "status": status,
         "hook-event": hook_event, "hooks-config": hooks_config}[args.command]()
    except (OSError, sqlite3.Error, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"researchctl: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
