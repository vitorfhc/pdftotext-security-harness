#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR=${1:-}

if [[ -z $PROJECT_DIR || $PROJECT_DIR != /* ]]; then
  echo "usage: $0 /absolute/project/path" >&2
  exit 2
fi

bundle=$SCRIPT_DIR/assets/research-skills.tgz
manifest=$SCRIPT_DIR/assets/research-skills.sha256
lock=$SCRIPT_DIR/assets/skills-lock.json
for required in "$bundle" "$manifest" "$lock"; do
  [[ -f $required ]] || {
    echo "Missing bundle asset: $required" >&2
    exit 1
  }
done

mkdir -p "$PROJECT_DIR/.agents"
staging=$(mktemp -d "$PROJECT_DIR/.agents/skills.new.XXXXXX")
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT

tar -xzf "$bundle" -C "$staging" --strip-components=1
find "$staging" -mindepth 1 -maxdepth 1 -type d | grep -q .

old=$PROJECT_DIR/.agents/skills.old
rm -rf "$old"
if [[ -d $PROJECT_DIR/.agents/skills ]]; then
  mv "$PROJECT_DIR/.agents/skills" "$old"
fi
mv "$staging" "$PROJECT_DIR/.agents/skills"
trap - EXIT

if ! (cd "$PROJECT_DIR" && sha256sum -c "$manifest" >/dev/null); then
  rm -rf "$PROJECT_DIR/.agents/skills"
  if [[ -d $old ]]; then
    mv "$old" "$PROJECT_DIR/.agents/skills"
  fi
  echo "Skill integrity verification failed; previous skills restored." >&2
  exit 1
fi

rm -rf "$old"
cp "$lock" "$PROJECT_DIR/skills-lock.json"
count=$(find "$PROJECT_DIR/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l)
echo "Installed and verified $count project-scoped skills in $PROJECT_DIR"
