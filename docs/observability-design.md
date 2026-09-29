# Observability design

## Goals

The harness separates passive execution telemetry from agent-declared research meaning.

- Passive hooks answer what ran, when, and whether a result returned.
- SQLite research records answer why an experiment existed, what it showed, and how beliefs changed.
- Full commands and evidence belong in experiment records and local artifacts, not passive telemetry.

`workspace/research.db` is canonical. Terminal transcripts and Codex session logs are supplementary.

## Passive hook telemetry

`workspace/scripts/researchctl.py hook-event` accepts Codex hook JSON on stdin and records:

- hook event name;
- session, turn, tool-use, and agent identifiers;
- tool name and outcome;
- input and response byte counts.

It does not retain prompt text, command bodies, environment values, tool output, PDFs, or credentials. Events larger than 1 MiB fail closed. Duplicate hook events are ignored by a stable key.

Generate project hook configuration after cloning because the command contains an absolute local path:

```bash
mkdir -p .codex
python3 workspace/scripts/researchctl.py hooks-config > .codex/hooks.json
```

Review the file and trust the hooks in Codex. Hooks may be unavailable on some tool paths, may complete out of order, or may be interrupted. Never derive experiment truth from hooks alone.

## Semantic records

The coordinator writes:

- hypotheses before selecting tests;
- experiments as `PLANNED` before execution;
- results, exit status, duration, build identity, and artifact paths immediately afterward;
- observations for evidence;
- conclusions for verdicts and impact;
- ChangeVectors for meaningful changes in direction.

Record a ChangeVector with:

```bash
cat <<'JSON' | python3 workspace/scripts/researchctl.py change-vector
{
  "decision": "Switch from parser fuzzing to a bounded decoder audit",
  "evidence_refs": ["experiment:12", "observation:31"],
  "reason": "The campaign plateaued and coverage shows an unexplored decoder path.",
  "next_action": "Delegate decoder validation tracing and design one discriminating input.",
  "alternatives_considered": ["extend the unchanged campaign"]
}
JSON
```

Do not store private reasoning. Keep the reason short and evidence-based.

## Failure behavior

If a canonical database write fails:

1. Preserve active experiment artifacts.
2. Stop starting new experiments.
3. Repair and integrity-check the database.
4. Reload active state and resume.

Do not reconstruct canonical decisions from model context or terminal history.

## Retention and sharing

Keep unique finding evidence until reviewed. Generated corpora, failed inputs, telemetry, databases, terminal logs, and reports are ignored by Git.

Before sharing a report, remove credentials, hostnames, usernames, IP addresses, notification topics, and host-specific paths. Never commit trigger PDFs or run databases to this repository.
