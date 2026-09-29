#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root so the configuration applies to root's Codex on this VPS." >&2
  exit 1
fi

command -v codex >/dev/null
command -v gdb-mcp >/dev/null

# These registrations are written by the Codex CLI on the current Linux VM.
# They do not touch the workstation that invoked SSH.
codex mcp add gdb -- /usr/local/bin/gdb-mcp
codex mcp add ghidra --url http://127.0.0.1:6050/mcp
codex mcp list
