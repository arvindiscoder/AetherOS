#!/usr/bin/env bash
# AetherOS shared build helpers. Sourced, never executed directly.
# shellcheck shell=bash

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''
fi

log()  { printf '%s[aether]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
step() { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLUE" "$*" "$C_RESET"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s warn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serror%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

on_error() {
  local rc=$?
  printf '\n%serror%s build failed at line %s (exit %s)\n' "$C_RED" "$C_RESET" "${BASH_LINENO[0]:-?}" "$rc" >&2
  printf 'Hint: inspect the last stage, then re-run. build/ is kept for debugging.\n' >&2
  exit "$rc"
}
trap on_error ERR

# ---------------------------------------------------------------------------
# Environment (build.sh exports the canonical values)
# ---------------------------------------------------------------------------
: "${AETHER_ROOT:?AETHER_ROOT is not set}"
: "${AETHER_BUILD:?AETHER_BUILD is not set}"
: "${AETHER_ROOTFS:?AETHER_ROOTFS is not set}"
: "${AETHER_ISO_DIR:?AETHER_ISO_DIR is not set}"
: "${AETHER_OUT:?AETHER_OUT is not set}"
: "${AETHER_SUITE:=trixie}"
: "${AETHER_ARCH:=amd64}"
: "${AETHER_MIRROR:=http://deb.debian.org/debian}"
: "${AETHER_SECURITY:=http://security.debian.org/debian-security}"
: "${AETHER_VERSION:=0.1}"
: "${AETHER_LOW_DISK:=1}"
: "${AETHER_CUSTOM_KERNEL:=0}"
: "${AETHER_ALLOW_LARGE:=0}"
: "${AETHER_KEEP_BUILD:=0}"
: "${AETHER_NO_BROWSER:=0}"

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C.UTF-8
export LANG=C.UTF-8
export APT_LISTCHANGES_FRONTEND=none

need_root() { [[ ${EUID:-1} -eq 0 ]] || die "run this as root (sudo ./build.sh)"; }
have() { command -v "$1" >/dev/null 2>&1; }
require_cmd() {
  local c
  for c in "$@"; do have "$c" || die "missing host command: $c"; done
}
human() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }
dir_size() { du -sb "$1" 2>/dev/null | awk '{print $1}'; }

# Run a command inside the target root with a sane, clean environment.
chroot_run() {
  chroot "$AETHER_ROOTFS" /usr/bin/env -i \
    HOME=/root TERM=xterm PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8 \
    "$@"
}

# apt wrapper that never installs recommends and never prompts.
aether_apt() {
  chroot_run apt-get -y \
    -o Acquire::Retries=3 \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o APT::Install-Recommends=false \
    -o APT::Install-Suggests=false \
    "$@"
}

# Try to install a package; never abort the build for an optional package.
aether_apt_soft() {
  local p
  for p in "$@"; do
    if aether_apt install --no-install-recommends "$p" >/dev/null 2>&1; then
      ok "optional package: $p"
    else
      warn "optional package unavailable, skipping: $p"
    fi
  done
}

# Free bytes on the filesystem containing $1.
free_bytes() { df -PB1 "$1" | awk 'NR==2 {print $4}'; }
require_free_gb() {
  local path=$1 need_gb=$2 free_gb
  free_gb=$(( $(free_bytes "$path") / 1024 / 1024 / 1024 ))
  if (( free_gb < need_gb )); then
    die "need at least ${need_gb} GB free on $path (have ${free_gb} GB). Use AETHER_BUILD on another disk."
  fi
}

# Best-effort cleanup of chroot mounts. Safe to call repeatedly.
unmount_chroot() {
  local m
  for m in dev/pts dev proc sys run; do
    if mountpoint -q "$AETHER_ROOTFS/$m" 2>/dev/null; then
      umount -l "$AETHER_ROOTFS/$m" 2>/dev/null || true
    fi
  done
}

# Purge transient build junk without touching installed package metadata.
low_disk_clean() {
  [[ ${AETHER_LOW_DISK:-0} == 1 ]] || return 0
  rm -rf "$AETHER_ROOTFS"/var/cache/apt/archives/*.deb \
         "$AETHER_ROOTFS"/var/cache/apt/archives/partial/* \
         "$AETHER_ROOTFS"/var/lib/apt/lists/* \
         "$AETHER_ROOTFS"/tmp/* "$AETHER_ROOTFS"/var/tmp/* 2>/dev/null || true
}

copy_tree() { # copy_tree <src> <dst>
  local src=$1 dst=$2
  [[ -e "$src" ]] || die "copy_tree: missing $src"
  mkdir -p "$dst"
  cp -a "$src"/. "$dst"/
}

install_file() { # install_file <src> <dst> [mode]
  local src=$1 dst=$2 mode=${3:-0644}
  [[ -f "$src" ]] || die "install_file: missing $src"
  install -D -m "$mode" "$src" "$dst"
}
