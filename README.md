# pdftotext security research harness

A reproducible Codex workspace for an authorized, long-running security review of Poppler 25.03.0 `pdftotext` on Linux.

The harness combines source review, AFL++, sanitizers, GDB/Pwndbg, GDB MCP, Ghidra MCP, CodeQL, Semgrep, project-scoped security skills, SQLite-backed research memory, ChangeVector decision records, and optional phone notifications.

It contains no findings, crashing PDFs, logs, credentials, cloud configuration, or prior run state.

## Requirements

- A dedicated Ubuntu 24.04 x86-64 VM.
- Codex CLI installed on that VM. The DigitalOcean Codex Universal image is the easiest option.
- At least 4 vCPUs, 8 GiB RAM, and 80 GiB disk. More disk and 16 GiB RAM are recommended for CodeQL and parallel builds.
- Authorization to research this target.

The supplied toolchain installer is designed for a disposable research VM and runs as root.

## Quick start

```bash
git clone <private-repository-url>
cd pdftotext-security-harness

sudo ./toolchain/bootstrap.sh --project "$PWD"
./scripts/init-project.sh
./scripts/build-target.sh

# Choose an explicit UTC deadline for the long-running Goal.
./scripts/render-goal.sh <YYYY-MM-DDTHH:MM:SSZ> > workspace/goal.txt

tmux new -s research
codex --approve-for-me
```

Inside Codex, paste the single `/goal` line from `workspace/goal.txt`. Read and approve the generated project hooks when Codex asks. If Codex is not authenticated, run `codex login --device-auth` first.

The run writes its canonical state to `workspace/research.db` and its report to `workspace/report/final-report.md`.

## Validate the toolchain

```bash
sudo /opt/pdfsec/verify.sh "$PWD"
workspace/scripts/verify_target_identity.sh
```

The first command exercises GDB, Pwndbg, rr, Semgrep, CodeQL, Ghidra, both MCP servers, Codex MCP registration, and the installed skills. `rr` may be unavailable on cloud CPUs that do not expose the required performance counters.

## Optional phone notifications

Copy the example configuration, choose a long random ntfy topic, and run the monitor in a second tmux window:

```bash
cp config/notifications.env.example config/notifications.env
$EDITOR config/notifications.env
set -a; . config/notifications.env; set +a
python3 scripts/notify-findings.py
```

The default notification includes the verdict and a short conclusion. It never uploads PDFs, logs, stack traces, commands, or artifact paths. Set `NTFY_INCLUDE_SUMMARY=0` for generic alerts only.

## Repository layout

- `AGENTS.md`: durable coordinator policy and evidence standard.
- `RUN_PROMPT.md`: threat model, objective, limits, and startup procedure.
- `prompts/`: focused prompts for source scouts, RCE escalation, and chain synthesis.
- `workspace/schema.sql`: canonical SQLite schema.
- `workspace/scripts/researchctl.py`: database initializer, ChangeVector recorder, hook adapter, and status command.
- `scripts/`: initialization, target build, identity verification, Goal rendering, notifications, and release checks.
- `toolchain/`: pinned Ubuntu toolchain and project-skill installer.
- `docs/observability-design.md`: what is recorded and what stays out of telemetry.

## Operating rules

Use only systems and inputs you are authorized to test. Keep the PDF-only threat model fixed. Preserve strong memory-safety evidence, distinguish demonstrated impact from hypotheses, and never claim RCE without repeatable controlled transfer. Do not publish or transmit samples or vulnerability details from an active run without an explicit disclosure decision.
