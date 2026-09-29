#!/usr/bin/env bash
set -Eeuo pipefail

deadline=${1:-}
if [[ -z $deadline ]]; then
  echo "usage: $0 YYYY-MM-DDTHH:MM:SSZ" >&2
  exit 2
fi

normalized=$(python3 - "$deadline" <<'PY'
import datetime as dt
import sys

value = sys.argv[1]
try:
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
except ValueError as exc:
    raise SystemExit(f"invalid ISO-8601 deadline: {exc}")
if parsed.tzinfo is None or parsed.utcoffset() != dt.timedelta(0):
    raise SystemExit("deadline must include UTC using Z or +00:00")
if parsed <= dt.datetime.now(dt.timezone.utc):
    raise SystemExit("deadline must be in the future")
print(parsed.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
)

printf '%s\n' "/goal Continue the authorized Poppler 25.03.0 pdftotext investigation described in AGENTS.md and RUN_PROMPT.md until ${normalized}. Seek and validate distinct impactful vulnerabilities triggered by PDF bytes alone. Preserve each confirmed finding and keep investigating new surfaces after it; a first finding does not complete this Goal. Persist canonical state in workspace/research.db, record meaningful direction changes as ChangeVectors, delegate source exploration aggressively, serialize heavy work through the shared lock, and obey the evidence and resource rules in the project files. For each memory-safety finding, explicitly test the missing disclosure, write-control, survival, and control-consumer bridges using inert proof only. At the deadline, stop new experiments, preserve active artifacts, reconcile SQLite state, write workspace/report/final-report.md, and complete the Goal. Pause only for a genuine blocker, a safety or resource limit that cannot be resolved within the stated limits, or an explicit user request."
