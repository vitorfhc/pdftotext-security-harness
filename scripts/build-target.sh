#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=$ROOT/config/target.env
[[ -f $CONFIG ]] || CONFIG=$ROOT/config/target.env.example
# shellcheck disable=SC1090
source "$CONFIG"

for command in git cmake ninja sha256sum ldd readlink flock; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

SRC=$ROOT/workspace/source/poppler-$POPPLER_VERSION
RELEASE=$ROOT/workspace/builds/pristine-release
SANITIZER=$ROOT/workspace/builds/pristine-sanitizer
LOCK=$ROOT/workspace/.research-heavy-worker.lock
mkdir -p "$(dirname "$SRC")" "$(dirname "$RELEASE")"

exec 9>"$LOCK"
if ! flock -n 9; then
  echo "Another heavy research task owns $LOCK" >&2
  exit 1
fi

if [[ ! -d $SRC/.git ]]; then
  git clone --filter=blob:none "$POPPLER_REPOSITORY" "$SRC"
fi

if [[ -n $(git -C "$SRC" status --porcelain) ]]; then
  echo "Refusing to modify a dirty pristine source tree: $SRC" >&2
  exit 1
fi

git -C "$SRC" fetch --force origin "$POPPLER_COMMIT"
git -C "$SRC" checkout --detach "$POPPLER_COMMIT"
actual_commit=$(git -C "$SRC" rev-parse HEAD)
[[ $actual_commit == "$POPPLER_COMMIT" ]] || {
  echo "Poppler commit mismatch: $actual_commit" >&2
  exit 1
}

common=(
  -G Ninja
  -DENABLE_GLIB=OFF
  -DENABLE_CPP=OFF
  -DENABLE_QT5=OFF
  -DENABLE_QT6=OFF
  -DENABLE_GOBJECT_INTROSPECTION=OFF
  -DENABLE_GTK_DOC=OFF
  -DENABLE_UNSTABLE_API_ABI_HEADERS=OFF
  -DBUILD_CPP_TESTS=OFF
  -DBUILD_GTK_TESTS=OFF
  -DBUILD_QT5_TESTS=OFF
  -DBUILD_QT6_TESTS=OFF
  -DBUILD_MANUAL_TESTS=OFF
)

cmake -S "$SRC" -B "$RELEASE" "${common[@]}" -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build "$RELEASE" --target pdftotext -j "$BUILD_JOBS"

san_flags='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer'
cmake -S "$SRC" -B "$SANITIZER" "${common[@]}" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_FLAGS="$san_flags" \
  -DCMAKE_CXX_FLAGS="$san_flags" \
  -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address,undefined' \
  -DCMAKE_SHARED_LINKER_FLAGS='-fsanitize=address,undefined'
cmake --build "$SANITIZER" --target pdftotext -j "$BUILD_JOBS"

binary=$(readlink -f "$RELEASE/utils/pdftotext")
sanitizer_binary=$(readlink -f "$SANITIZER/utils/pdftotext")
openjpeg_link=$(ldd "$binary" | awk '/libopenjp2\.so/ {print $3; exit}')
[[ -n $openjpeg_link && -e $openjpeg_link ]] || {
  echo "The release binary did not resolve libopenjp2." >&2
  exit 1
}
openjpeg=$(readlink -f "$openjpeg_link")

binary_sha=$(sha256sum "$binary" | awk '{print $1}')
sanitizer_sha=$(sha256sum "$sanitizer_binary" | awk '{print $1}')
openjpeg_sha=$(sha256sum "$openjpeg" | awk '{print $1}')

cat >"$ROOT/workspace/target-identity.env" <<EOF
TARGET_COMMIT=$actual_commit
TARGET_BINARY=$binary
TARGET_BINARY_SHA256=$binary_sha
SANITIZER_BINARY=$sanitizer_binary
SANITIZER_BINARY_SHA256=$sanitizer_sha
OPENJPEG_LIBRARY=$openjpeg
OPENJPEG_SHA256=$openjpeg_sha
EOF
chmod 600 "$ROOT/workspace/target-identity.env"

{
  echo "created_utc=$(date -u +%FT%TZ)"
  echo "poppler_version=$POPPLER_VERSION"
  echo "poppler_commit=$actual_commit"
  echo "release_binary=$binary"
  echo "release_sha256=$binary_sha"
  echo "sanitizer_binary=$sanitizer_binary"
  echo "sanitizer_sha256=$sanitizer_sha"
  echo "openjpeg_library=$openjpeg"
  echo "openjpeg_sha256=$openjpeg_sha"
  echo "compiler=$(${CXX:-c++} --version | head -1)"
  echo
  echo "release_ldd:"
  ldd "$binary"
} >"$ROOT/workspace/target-identity.txt"

"$ROOT/workspace/scripts/verify_target_identity.sh"
echo "Target builds and identities are ready."
