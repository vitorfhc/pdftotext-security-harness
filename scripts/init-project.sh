#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p \
  workspace/{artifacts,builds,campaigns,corpus,crashes,logs,report,source,subagents,triage} \
  .codex

if [[ ! -f config/target.env ]]; then
  cp config/target.env.example config/target.env
  echo "Created config/target.env from the tracked example."
fi

python3 workspace/scripts/researchctl.py init

hooks_tmp=$(mktemp .codex/hooks.json.XXXXXX)
python3 workspace/scripts/researchctl.py hooks-config >"$hooks_tmp"
chmod 600 "$hooks_tmp"
mv "$hooks_tmp" .codex/hooks.json

echo "Project initialized."
echo "Review .codex/hooks.json and trust the project hooks in Codex."
echo "Next: ./scripts/build-target.sh"
