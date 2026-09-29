#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

while IFS= read -r -d '' script; do
  bash -n "$script"
done < <(find scripts toolchain workspace/scripts -type f -name '*.sh' -print0)

python3 -m py_compile workspace/scripts/researchctl.py scripts/notify-findings.py

scratch=$(mktemp -d)
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT
mkdir -p "$scratch/workspace/scripts"
cp workspace/schema.sql "$scratch/workspace/schema.sql"
cp workspace/scripts/researchctl.py "$scratch/workspace/scripts/researchctl.py"
(
  cd "$scratch"
  python3 workspace/scripts/researchctl.py init >/dev/null
  python3 workspace/scripts/researchctl.py status >/dev/null
  python3 workspace/scripts/researchctl.py hooks-config >/dev/null
)

scan_files=$(find . -type f -not -path './.git/*' -not -path './scripts/check-release.sh' -not -name '*.tgz' -not -name '*.zip' -not -name '*.zst')
patterns=(
  'BEGIN [A-Z ]*PRIVATE KEY'
  'github_pat_[A-Za-z0-9_]+'
  'ghp_[A-Za-z0-9]+'
  'DIGITALOCEAN_ACCESS_TOKEN='
  '/Users/'
  'codex-calm-'
  '159\.203\.'
)
for pattern in "${patterns[@]}"; do
  if grep -EIn "$pattern" $scan_files; then
    echo "Release check failed: matched sensitive or run-specific pattern: $pattern" >&2
    exit 1
  fi
done

if find . -type f \( -name 'research.db*' -o -name '*.pdf' -o -name '*.core' \) -print -quit | grep -q .; then
  echo "Release check failed: run evidence is present." >&2
  exit 1
fi

echo "Release checks passed."
