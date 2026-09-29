#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=${1:-/root/workspace/pdf-security-research}
REPORT_ROOT=/var/lib/pdfsec/validation
RUN_ID=$(date -u +%Y%m%dT%H%M%SZ)
RUN=$REPORT_ROOT/$RUN_ID
LOG=$RUN/verify.log
RESULTS=$RUN/results.tsv
mkdir -p "$RUN"
exec > >(tee -a "$LOG") 2>&1

printf 'test\tstatus\tdetail\n' >"$RESULTS"
ghidra_started=0

finalize() {
  local rc=$?
  set +e
  if (( ghidra_started )); then
    pdfsec-ghidra-mcp stop >/dev/null 2>&1
  fi
  {
    echo "# PDF security VPS validation"
    echo
    echo "- Timestamp: $(date -u +%FT%TZ)"
    echo "- Host: $(hostname)"
    echo "- Kernel: $(uname -r)"
    echo "- Project: $PROJECT_DIR"
    echo "- Validator exit status: $rc"
    echo
    echo '| Test | Status | Detail |'
    echo '|---|---|---|'
    tail -n +2 "$RESULTS" | while IFS=$'\t' read -r name status detail; do
      printf '| %s | %s | %s |\n' "$name" "$status" "$detail"
    done
  } >"$RUN/report.md"
  find "$RUN" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >"$RUN/SHA256SUMS"
  ln -sfn "$RUN" "$REPORT_ROOT/latest"
  echo "Validation report: $RUN/report.md"
  exit "$rc"
}
trap finalize EXIT

pass() { printf '%s\tPASS\t%s\n' "$1" "$2" | tee -a "$RESULTS"; }
warn() { printf '%s\tWARN\t%s\n' "$1" "$2" | tee -a "$RESULTS"; }
fail() { printf '%s\tFAIL\t%s\n' "$1" "$2" | tee -a "$RESULTS"; return 1; }

cat >"$RUN/smoke.c" <<'EOF'
#include <stdio.h>
#include <string.h>
static int add(int a, int b) { return a + b; }
int main(int argc, char **argv) {
  char dst[16] = {0};
  if (argc > 1) strcpy(dst, argv[1]);
  printf("%d %s\n", add(2, 3), dst);
  return 0;
}
EOF
gcc -g -O0 -fno-omit-frame-pointer -o "$RUN/smoke" "$RUN/smoke.c"

codex --version | tee "$RUN/codex-version.txt"
pass codex "$(head -1 "$RUN/codex-version.txt")"

gdb --version | head -1 | tee "$RUN/gdb-version.txt"
gdb -q -batch -ex 'break add' -ex run -ex bt -ex 'info registers rip rsp' \
  --args "$RUN/smoke" hello >"$RUN/gdb-smoke.txt" 2>&1
if grep -q 'Breakpoint 1' "$RUN/gdb-smoke.txt"; then
  pass gdb "breakpoint and backtrace worked"
else
  fail gdb "breakpoint test failed"
fi

pwndbg --version >"$RUN/pwndbg-version.txt" 2>&1
pwndbg -q -batch -ex "file $RUN/smoke" -ex checksec -ex quit >"$RUN/pwndbg-smoke.txt" 2>&1
if grep -Eqi 'PIE|RELRO|NX' "$RUN/pwndbg-smoke.txt"; then
  pass pwndbg "standalone Pwndbg checksec worked"
else
  fail pwndbg "checksec output missing"
fi

if rr record -n -o "$RUN/rr-trace" "$RUN/smoke" hello >"$RUN/rr-record.txt" 2>&1; then
  rr replay -a "$RUN/rr-trace" >"$RUN/rr-replay.txt" 2>&1
  pass rr "record and replay worked"
else
  warn rr "installed, but record failed on this virtual CPU; see rr-record.txt"
fi

cat >"$RUN/semgrep-rule.yml" <<'EOF'
rules:
  - id: smoke-strcpy
    languages: [c]
    severity: WARNING
    message: smoke test found strcpy
    pattern: strcpy(...)
EOF
semgrep --metrics=off --config "$RUN/semgrep-rule.yml" --json "$RUN/smoke.c" \
  >"$RUN/semgrep.json"
python3 - "$RUN/semgrep.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert any(r.get("check_id","").endswith("smoke-strcpy") for r in d["results"])
PY
pass semgrep "local offline rule found the fixture"

codeql version | tee "$RUN/codeql-version.txt"
codeql resolve languages >"$RUN/codeql-languages.txt"
codeql database create "$RUN/codeql-db" --language=cpp \
  --source-root="$RUN" \
  --command="gcc -g -O0 -o $RUN/codeql-smoke $RUN/smoke.c" \
  --overwrite >"$RUN/codeql-create.txt" 2>&1
if codeql database analyze "$RUN/codeql-db" \
    codeql/cpp-queries:codeql-suites/cpp-security-and-quality.qls \
    --format=sarifv2.1.0 --output="$RUN/codeql.sarif" \
    --threads=0 >"$RUN/codeql-analyze.txt" 2>&1; then
  [[ -s $RUN/codeql.sarif ]] && pass codeql "C database and standard suite completed"
else
  fail codeql "analysis failed; see codeql-analyze.txt"
fi

rm -rf "$RUN/ghidra-project"
mkdir -p "$RUN/ghidra-project"
ghidra-analyze-headless "$RUN/ghidra-project" smoke-project \
  -import "$RUN/smoke" -overwrite -deleteProject >"$RUN/ghidra-headless.txt" 2>&1
if grep -q 'ANALYZING' "$RUN/ghidra-headless.txt"; then
  pass ghidra "headless import and analysis worked"
else
  fail ghidra "headless analysis marker missing"
fi

cat >"$RUN/mcp-probe.py" <<'PY'
import asyncio, json, sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from mcp.client.streamable_http import streamablehttp_client

def payload(result):
    if result.structuredContent is not None:
        return result.structuredContent
    text="\n".join(
        item.text for item in result.content if getattr(item,"text",None) is not None
    )
    return json.loads(text)

async def stdio_probe(command, args, output, target):
    params=StdioServerParameters(command=command,args=args,env=None)
    async with stdio_client(params) as (read,write):
        async with ClientSession(read,write) as session:
            await session.initialize()
            result=await session.list_tools()
            names=sorted(t.name for t in result.tools)
            assert names
            record={"tools":names}
            created=payload(await session.call_tool("gdb_create_session",{"program":target}))
            assert created.get("ok"), created
            sid=created["session"]["session_id"]
            record["create_session"]=created
            try:
                bp=payload(await session.call_tool("gdb_set_breakpoint",{
                    "session_id":sid,"location":"add"
                }))
                assert bp.get("ok"), bp
                run=payload(await session.call_tool("gdb_run_and_context",{
                    "session_id":sid,"args":["hello"],"timeout":10.0
                }))
                assert run.get("ok"), run
                record["breakpoint"]=bp
                record["run_and_context"]=run
            finally:
                record["close_session"]=payload(await session.call_tool(
                    "gdb_close_session",{"session_id":sid}
                ))
            open(output,"w").write(json.dumps(record,indent=2))

async def http_probe(url, output):
    async with streamablehttp_client(url) as (read,write,*_):
        async with ClientSession(read,write) as session:
            await session.initialize()
            result=await session.list_tools()
            names=sorted(t.name for t in result.tools)
            assert names
            context=payload(await session.call_tool("context",{}))
            assert context
            open(output,"w").write(json.dumps({"tools":names,"context":context},indent=2))

mode=sys.argv[1]
if mode == "stdio":
    asyncio.run(stdio_probe(sys.argv[2],sys.argv[3:-2],sys.argv[-2],sys.argv[-1]))
else:
    asyncio.run(http_probe(sys.argv[2],sys.argv[3]))
PY

/opt/pdfsec/venvs/gdb-mcp/bin/python "$RUN/mcp-probe.py" stdio \
  /usr/local/bin/gdb-mcp "$RUN/gdb-mcp-tools.json" "$RUN/smoke"
if grep -q 'gdb_create_session' "$RUN/gdb-mcp-tools.json" && \
    grep -q 'run_and_context' "$RUN/gdb-mcp-tools.json"; then
  pass gdb-mcp "MCP session, breakpoint, run, context, and close worked"
else
  fail gdb-mcp "expected tool missing"
fi

pdfsec-ghidra-mcp start "$RUN/smoke"
ghidra_started=1
/opt/pdfsec/venvs/mcpyghidra/bin/python "$RUN/mcp-probe.py" http \
  http://127.0.0.1:6050/mcp "$RUN/ghidra-mcp-tools.json"
if grep -Eqi 'decomp|disassembl' "$RUN/ghidra-mcp-tools.json" && \
    grep -q 'program' "$RUN/ghidra-mcp-tools.json"; then
  pass ghidra-mcp "MCP context analysis and tools/list worked"
else
  fail ghidra-mcp "analysis tools missing"
fi

if ss -ltnp | awk '$4 ~ /:6050$/ && $4 !~ /^(127\.0\.0\.1|\[::1\]):/ {bad=1} END{exit bad}'; then
  pass mcp-network "Ghidra MCP is loopback-only"
else
  fail mcp-network "Ghidra MCP is exposed beyond loopback"
fi
pdfsec-ghidra-mcp stop
ghidra_started=0

codex mcp list >"$RUN/codex-mcp-list.txt"
if grep -q gdb "$RUN/codex-mcp-list.txt" && grep -q ghidra "$RUN/codex-mcp-list.txt"; then
  pass codex-mcp-config "gdb and ghidra are registered on this VM"
else
  fail codex-mcp-config "registration missing"
fi

skill_count=$(find "$PROJECT_DIR/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)
if (( skill_count >= 24 )); then
  pass skills "$skill_count project-scoped skills verified"
else
  fail skills "expected at least 24 skills, found $skill_count"
fi

if grep -q $'\tFAIL\t' "$RESULTS"; then
  exit 1
fi
