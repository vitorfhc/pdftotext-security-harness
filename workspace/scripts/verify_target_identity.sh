#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORKSPACE=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
IDENTITY=$WORKSPACE/target-identity.env

[[ -f $IDENTITY ]] || {
  echo "Missing $IDENTITY; run scripts/build-target.sh first." >&2
  exit 1
}

# This file is generated locally by scripts/build-target.sh and is never committed.
# shellcheck disable=SC1090
source "$IDENTITY"

failed=0
check_file() {
  local label=$1 path=$2 expected=$3 actual
  if [[ ! -f $path ]]; then
    echo "FAIL: $label is missing: $path" >&2
    failed=1
    return
  fi
  actual=$(sha256sum "$path" | awk '{print $1}')
  printf '%s_path=%s\n%s_sha256=%s\n' "$label" "$path" "$label" "$actual"
  if [[ $actual != "$expected" ]]; then
    echo "FAIL: $label hash differs from the frozen identity" >&2
    failed=1
  fi
}

check_file pdftotext "$TARGET_BINARY" "$TARGET_BINARY_SHA256"
check_file sanitizer "$SANITIZER_BINARY" "$SANITIZER_BINARY_SHA256"

resolved=$(ldd "$TARGET_BINARY" | awk '/libopenjp2\.so/ {print $3; exit}')
if [[ -z $resolved || ! -e $resolved ]]; then
  echo "FAIL: OpenJPEG did not resolve for $TARGET_BINARY" >&2
  failed=1
else
  resolved=$(readlink -f "$resolved")
  check_file openjpeg "$resolved" "$OPENJPEG_SHA256"
  if [[ $resolved != "$OPENJPEG_LIBRARY" ]]; then
    echo "FAIL: OpenJPEG resolved to a different path" >&2
    failed=1
  fi
fi

source_tree=$WORKSPACE/source/poppler-25.03.0
if [[ ! -d $source_tree/.git || $(git -C "$source_tree" rev-parse HEAD) != "$TARGET_COMMIT" ]]; then
  echo "FAIL: source commit differs from the frozen identity" >&2
  failed=1
fi

"$TARGET_BINARY" -v 2>&1 | sed -n '1,2p'
(( failed == 0 )) || exit 1
echo "PASS: frozen target identity verified"
