# PDF security research VPS bootstrap

This bundle installs and validates the Linux tooling used by the Xpdf and Poppler research agents. It is intended for an Ubuntu 24.04 x86-64 DigitalOcean Codex Universal droplet.

## Installed components

- GDB, GDBserver, `rr`, Valgrind, strace, ltrace, LLVM/Clang, AFL++, build tools, debug symbols, and parser build dependencies.
- Pwndbg as the separate `pwndbg` command. It does not modify `.gdbinit`, so GDB MCP receives clean GDB/MI output.
- GDB MCP pinned to a verified repository commit.
- Ghidra with Java 21.
- MCPyGhidra in headless mode, bound to `127.0.0.1:6050`.
- CodeQL CLI and standard query packs.
- Semgrep in an isolated Python environment.
- Project-scoped Trail of Bits, Yaklang, and focused binary-analysis skills.
- `tmux`, SQLite, ripgrep, jq, shellcheck, and supporting utilities.

## Install

Copy this entire directory to the droplet, then run:

```bash
sudo ./bootstrap.sh --project /root/workspace/your-project
```

The script is idempotent. Pinned archives are cached under `/opt/pdfsec/cache` and checked with SHA-256 before extraction. MCP configuration is written by the `codex` executable on that Linux VM only.

Install the same verified skills into another project without reinstalling the tools:

```bash
sudo /opt/pdfsec/install-project-skills.sh /root/workspace/another-project
```

## Validate

```bash
sudo /opt/pdfsec/verify.sh /root/workspace/your-project
```

The validator performs real smoke tests for GDB, Pwndbg, rr, Semgrep, CodeQL, Ghidra headless analysis, both MCP protocol handshakes, Codex MCP registration, skill integrity, and loopback-only MCP listening. Reports are saved under `/var/lib/pdfsec/validation/`.

`rr` may install correctly but fail to record if the cloud hypervisor does not expose the performance counters it requires. The validator records that as a warning and preserves the exact error.

## Use Ghidra MCP for a binary

```bash
pdfsec-ghidra-mcp start /absolute/path/to/pdftotext
pdfsec-ghidra-mcp status
pdfsec-ghidra-mcp log
pdfsec-ghidra-mcp stop
```

Start the server for the desired binary before starting or restarting Codex so the Ghidra tools are available when the session discovers MCP servers.

## Authentication

The installer does not copy Codex credentials between machines. If the droplet is not already authenticated, run:

```bash
codex login --device-auth
```

Device authentication is the only expected manual step.
