# Poppler 25.03.0 pdftotext research run

Read `AGENTS.md` before starting. Run this investigation only on an authorized Linux research system.

## Objective

Find and validate impactful vulnerabilities in Poppler 25.03.0 `pdftotext` under this invocation:

```text
pdftotext input.pdf output.txt
```

The attacker controls only `input.pdf` bytes. Keep CLI arguments, output path, environment, configuration, installed fonts, and filesystem state fixed. Pure denial of service does not count.

## Start the run

1. Run `./scripts/init-project.sh`.
2. Run `./scripts/build-target.sh` and `workspace/scripts/verify_target_identity.sh`.
3. Choose an explicit UTC deadline and generate the Goal with `./scripts/render-goal.sh <ISO-8601-UTC> > workspace/goal.txt`.
4. Start Codex from this repository in tmux.
5. Submit the generated `/goal` line as a standalone interactive Codex command. Passing it as a normal positional prompt does not activate Goal mode.

At startup, record measured resources, effective limits, start time, deadline, source identity, binary identity, and material library identities in `run_metadata`. Verify the database and ChangeVector recorder before experiments.

Form an attack-surface map with narrow source questions delegated to subagents. Then choose experiments based on evidence.

## Research expectations

Persist hypotheses, plans, results, observations, decisions, and conclusions continuously in SQLite. Delegate noisy source exploration. Use AFL++, structured PDF mutation, sanitizers, debuggers, CodeQL, Semgrep, and differential analysis when they answer a specific question.

Preserve every sanitizer-confirmed OOB read/write and comparable signal. Continue into root-cause and primitive analysis. When a known crash blocks fuzzing, preserve it, neutralize it in a separate research build, continue, and validate every additional candidate on pristine 25.03.0.

For each confirmed corruption, determine whether the same process provides an address disclosure, useful destination/value control, survival to a control-sensitive consumer, and an inert controlled-transfer proof. Record a clear negative result when a bridge is absent.

## Default resource limits

- Review each fuzzing campaign at least hourly.
- Run at most two CPU-intensive workers unless the VM has enough resources and the database records a higher explicit limit.
- Keep research memory below the smaller of 8 GiB or half of measured RAM.
- Keep the research workspace below 40 GiB.
- Pause new heavy work when free disk is below 15 GiB or 20% of the filesystem, whichever is larger.
- Use timeouts, process limits, and the shared heavy-work lock.

If the system is too small for a safe task, record the constraint and choose a lighter experiment. If Codex pauses because of account capacity or service interruption, resume the same Goal and reload SQLite state.

At the deadline, stop new experiments, preserve active artifacts, reconcile database state, and write `workspace/report/final-report.md`. Save findings locally. The user decides whether and how to disclose them.
