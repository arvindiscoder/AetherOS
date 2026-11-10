#!/usr/bin/env bash
# Reclaim build space. Safe by default: only build/ and generated out/ files.
#
#   sudo ./scripts/clean.sh              # remove build/ and generated ISOs
#   sudo ./scripts/clean.sh --build      # remove build/ only
#   sudo ./scripts/clean.sh --out        # remove generated ISOs only
#   sudo ./scripts/clean.sh --dry-run
set -Eeuo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export AETHER_ROOT="$ROOT_DIR"
export AETHER_BUILD="${AETHER_BUILD:-$ROOT_DIR/build}"
export AETHER_ROOTFS="${AETHER_ROOTFS:-$AETHER_BUILD/rootfs}"
export AETHER_ISO_DIR="${AETHER_ISO_DIR:-$AETHER_BUILD/iso}"
export AETHER_OUT="${AETHER_OUT:-$ROOT_DIR/out}"
export AETHER_SUITE="${AETHER_SUITE:-trixie}"
export AETHER_ARCH="${AETHER_ARCH:-amd64}"
export AETHER_MIRROR="${AETHER_MIRROR:-http://deb.debian.org/debian}"
export AETHER_SECURITY="${AETHER_SECURITY:-http://security.debian.org/debian-security}"
export AETHER_VERSION="${AETHER_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.1)}"

# shellcheck source=lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

DO_BUILD=1
DO_OUT=1
DRY=0
while (($#)); do
  case "$1" in
    --build) DO_OUT=0 ;;
    --out)   DO_BUILD=0 ;;
    --all)   DO_BUILD=1; DO_OUT=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

[[ ${EUID:-1} -eq 0 ]] || die "run as root so chroot mounts and root-owned files can be removed"

if (( DO_BUILD )); then
  if [[ -d "$AETHER_ROOTFS" ]]; then
    unmount_chroot
  fi
  if (( DRY )); then
    log "would remove: $AETHER_BUILD"
  else
    rm -rf "$AETHER_BUILD"
    ok "removed $AETHER_BUILD"
  fi
fi

if (( DO_OUT )); then
  if (( DRY )); then
    log "would remove generated files in: $AETHER_OUT"
  else
    rm -f "$AETHER_OUT"/aetheros-*.iso \
          "$AETHER_OUT"/aetheros-*.iso.sha256 \
          "$AETHER_OUT"/aetheros-*.manifest.txt \
          "$AETHER_OUT"/aetheros-*-boot.txt 2>/dev/null || true
    ok "removed generated ISOs and manifests from $AETHER_OUT"
  fi
fi

log "free space: $(df -h "$ROOT_DIR" | awk 'NR==2 {print $4}') available on this filesystem"
