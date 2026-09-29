# Third-party components

The toolchain installer downloads pinned releases from their upstream projects. Each component remains subject to its upstream license.

- Ghidra: National Security Agency.
- Pwndbg: Pwndbg project.
- CodeQL CLI bundle: GitHub.
- Semgrep: Semgrep.
- GDB MCP: `BeaCox/gdb-mcp`.
- MCPyGhidra: `nightwing-us/mcpyghidra`.

The project-scoped skill bundle contains selected skills from:

- `trailofbits/skills`.
- `yaklang/hack-skills`.
- `wshobson/agents`.

Pinned sources, paths, and content hashes are recorded in `skills-lock.json` and `toolchain/assets/skills-lock.json`. Review the upstream licenses before redistributing the skills outside this private repository.
