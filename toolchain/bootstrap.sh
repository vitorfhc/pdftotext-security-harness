#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The path is resolved relative to this installer at runtime.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/versions.env"

PROJECT_DIR=/root/workspace/pdf-security-research
if [[ ${1:-} == "--project" && -n ${2:-} ]]; then
  PROJECT_DIR=$2
elif [[ $# -ne 0 ]]; then
  echo "usage: sudo $0 [--project /absolute/project/path]" >&2
  exit 2
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi
if [[ $PROJECT_DIR != /* ]]; then
  echo "Project path must be absolute: $PROJECT_DIR" >&2
  exit 1
fi
if [[ $(uname -m) != x86_64 ]]; then
  echo "This pinned build currently supports x86_64 only." >&2
  exit 1
fi
# shellcheck disable=SC1091
if ! . /etc/os-release || [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
  echo "This installer is validated for Ubuntu 24.04 only." >&2
  exit 1
fi

ROOT=/opt/pdfsec
CACHE=$ROOT/cache
VENV=$ROOT/venvs
STATE=/var/lib/pdfsec
LOG_DIR=/var/log/pdfsec
INSTALL_LOG=$LOG_DIR/bootstrap.log
mkdir -p "$CACHE" "$VENV" "$STATE" "$LOG_DIR" "$PROJECT_DIR"
exec > >(tee -a "$INSTALL_LOG") 2>&1

echo "[$(date -u +%FT%TZ)] bootstrap start project=$PROJECT_DIR"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  apt-transport-https autoconf automake bash-completion binutils binutils-multiarch \
  bison build-essential ca-certificates ccache checksec clang cmake curl elfutils \
  file flex g++ gcc gdb gdb-multiarch gdbserver git git-lfs jq less libboost-dev \
  libc6-dbg libc6-dev-i386 libcairo2-dev libcapstone-dev libcurl4-openssl-dev \
  libfontconfig1-dev libfreetype6-dev libgmp-dev libjpeg-dev liblcms2-dev \
  libopenjp2-7-dev libpng-dev libssl-dev libtiff-dev libtool libxml2-dev \
  lld lldb llvm ltrace make meson nasm ninja-build openjdk-21-jdk-headless \
  patchelf pipx pkg-config python3-dev python3-pip python3-venv qemu-user \
  qemu-user-static ripgrep rr rsync shellcheck sqlite3 strace tmux unzip \
  valgrind wget xz-utils zip zlib1g-dev zstd afl++

download_verified() {
  local url=$1 expected=$2 destination=$3
  if [[ -f $destination ]] && echo "$expected  $destination" | sha256sum -c - >/dev/null 2>&1; then
    echo "verified cached $(basename "$destination")"
    return
  fi
  local temporary=${destination}.partial
  rm -f "$temporary"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 4 \
    --retry-delay 2 --output "$temporary" "$url"
  echo "$expected  $temporary" | sha256sum -c -
  mv "$temporary" "$destination"
}

replace_symlink() {
  local target=$1 link=$2
  ln -sfn "$target" "$link"
}

install_ghidra() {
  local archive=$CACHE/ghidra-${GHIDRA_VERSION}.zip
  local install=/opt/ghidra/ghidra_${GHIDRA_VERSION}_PUBLIC
  download_verified "$GHIDRA_URL" "$GHIDRA_SHA256" "$archive"
  if [[ ! -x $install/support/analyzeHeadless ]]; then
    mkdir -p /opt/ghidra
    rm -rf "$install"
    unzip -q "$archive" -d /opt/ghidra
  fi
  replace_symlink "$install" /opt/ghidra/current
  replace_symlink /opt/ghidra/current/support/analyzeHeadless /usr/local/bin/ghidra-analyze-headless
}

install_codeql() {
  local archive=$CACHE/codeql-${CODEQL_VERSION}-cpp-linux64.tar.zst
  local install=/opt/codeql/$CODEQL_VERSION
  download_verified "$CODEQL_URL" "$CODEQL_SHA256" "$archive"
  if [[ ! -x $install/codeql/codeql ]] || \
      [[ $(cat "$install/.bundle-sha256" 2>/dev/null || true) != "$CODEQL_SHA256" ]]; then
    rm -rf "$install"
    mkdir -p "$install"
    tar --zstd -xf "$archive" -C "$install"
    echo "$CODEQL_SHA256" >"$install/.bundle-sha256"
  fi
  replace_symlink "$install/codeql/codeql" /usr/local/bin/codeql
}

install_pwndbg() {
  local archive=$CACHE/pwndbg-${PWNDBG_VERSION}-x86_64-portable.tar.xz
  local install=/opt/pwndbg/$PWNDBG_VERSION
  download_verified "$PWNDBG_URL" "$PWNDBG_SHA256" "$archive"
  if [[ ! -e $install/.installed ]]; then
    rm -rf "$install"
    mkdir -p "$install"
    tar -xJf "$archive" -C "$install" --strip-components=1
    touch "$install/.installed"
  fi
  local launcher
  # The portable archive currently expands as pwndbg/{bin,exe,lib,...}.
  # Keep discovery tolerant of a future flat archive while preferring its
  # documented bin launcher.
  if [[ -x $install/pwndbg/bin/pwndbg ]]; then
    launcher=$install/pwndbg/bin/pwndbg
  else
    launcher=$(find "$install" -maxdepth 4 -type f -name pwndbg -perm -111 -print -quit)
  fi
  if [[ -z $launcher ]]; then
    echo "Pwndbg launcher was not found after extraction." >&2
    return 1
  fi
  replace_symlink "$launcher" /usr/local/bin/pwndbg
}

install_python_tools() {
  python3 -m venv "$VENV/semgrep"
  "$VENV/semgrep/bin/pip" install --disable-pip-version-check --upgrade pip wheel
  "$VENV/semgrep/bin/pip" install --disable-pip-version-check "semgrep==$SEMGREP_VERSION"
  replace_symlink "$VENV/semgrep/bin/semgrep" /usr/local/bin/semgrep

  local gdb_checkout=$ROOT/src/gdb-mcp
  mkdir -p "$ROOT/src"
  if [[ ! -d $gdb_checkout/.git ]]; then
    git clone --filter=blob:none "$GDB_MCP_REPOSITORY" "$gdb_checkout"
  fi
  git -C "$gdb_checkout" fetch --force origin "$GDB_MCP_COMMIT"
  git -C "$gdb_checkout" checkout --detach "$GDB_MCP_COMMIT"
  [[ $(git -C "$gdb_checkout" rev-parse HEAD) == "$GDB_MCP_COMMIT" ]]
  python3 -m venv "$VENV/gdb-mcp"
  "$VENV/gdb-mcp/bin/pip" install --disable-pip-version-check --upgrade pip wheel
  "$VENV/gdb-mcp/bin/pip" install --disable-pip-version-check "$gdb_checkout"
  replace_symlink "$VENV/gdb-mcp/bin/gdb-mcp" /usr/local/bin/gdb-mcp

  local wheel=$CACHE/mcpyghidra-${MCPYGHIDRA_VERSION}-py3-none-any.whl
  download_verified "$MCPYGHIDRA_URL" "$MCPYGHIDRA_SHA256" "$wheel"
  python3 -m venv "$VENV/mcpyghidra"
  "$VENV/mcpyghidra/bin/pip" install --disable-pip-version-check --upgrade pip wheel
  "$VENV/mcpyghidra/bin/pip" install --disable-pip-version-check "$wheel"
}

install_skills() {
  "$SCRIPT_DIR/install-project-skills.sh" "$PROJECT_DIR"
}

install_wrappers() {
  install -m 0755 "$SCRIPT_DIR/bin/pdfsec-ghidra-mcp" /usr/local/bin/pdfsec-ghidra-mcp
  install -m 0755 "$SCRIPT_DIR/configure-codex-mcp.sh" "$ROOT/configure-codex-mcp.sh"
  install -m 0755 "$SCRIPT_DIR/install-project-skills.sh" "$ROOT/install-project-skills.sh"
  rm -rf "$ROOT/assets"
  cp -a "$SCRIPT_DIR/assets" "$ROOT/assets"
  install -m 0644 "$SCRIPT_DIR/versions.env" "$ROOT/versions.env"
  install -m 0755 "$SCRIPT_DIR/verify.sh" "$ROOT/verify.sh"
}

configure_system() {
  cat >/etc/sysctl.d/60-pdfsec-debug.conf <<'EOF'
# Dedicated research VM: allow rr/perf use by local processes.
kernel.perf_event_paranoid = 1
EOF
  sysctl --system >/dev/null || true
  mkdir -p /root/workspace
  if command -v codex >/dev/null 2>&1; then
    codex --version
  else
    echo "Codex is absent. Use the DigitalOcean Codex Universal image." >&2
    return 1
  fi
}

install_ghidra
install_codeql
install_pwndbg
install_python_tools
install_skills
install_wrappers
configure_system
"$ROOT/configure-codex-mcp.sh"

{
  echo "installed_at=$(date -u +%FT%TZ)"
  echo "project_dir=$PROJECT_DIR"
  echo "host=$(hostname)"
  sha256sum "$SCRIPT_DIR/versions.env" "$SCRIPT_DIR/assets/research-skills.tgz"
} >"$STATE/install-identity.txt"

echo "[$(date -u +%FT%TZ)] bootstrap complete"
echo "Run: $ROOT/verify.sh '$PROJECT_DIR'"
