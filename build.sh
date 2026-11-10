#!/usr/bin/env bash
# AetherOS master build orchestrator.
#
#   sudo ./build.sh                 # core ISO, low-disk mode
#   sudo ./build.sh --check         # host checks only
#   sudo ./build.sh --custom-kernel # compile a low-latency kernel (slow, +2.5 GB)
#   sudo ./build.sh --keep-build    # keep build/rootfs for debugging
#   sudo ./build.sh --allow-large   # don't fail if ISO > 512 MB
#
# Everything is driven by the numbered scripts in scripts/. Each stage is
# idempotent enough to re-run after a failure; start from scratch with
# scripts/clean.sh --build.
set -Eeuo pipefail
umask 022

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export AETHER_VERSION="${AETHER_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.1)}"
export AETHER_ROOT="$ROOT_DIR"
export AETHER_BUILD="${AETHER_BUILD:-$ROOT_DIR/build}"
export AETHER_ROOTFS="${AETHER_ROOTFS:-$AETHER_BUILD/rootfs}"
export AETHER_ISO_DIR="${AETHER_ISO_DIR:-$AETHER_BUILD/iso}"
export AETHER_OUT="${AETHER_OUT:-$ROOT_DIR/out}"
export AETHER_SUITE="${AETHER_SUITE:-trixie}"
export AETHER_ARCH="${AETHER_ARCH:-amd64}"
export AETHER_MIRROR="${AETHER_MIRROR:-http://deb.debian.org/debian}"
export AETHER_SECURITY="${AETHER_SECURITY:-http://security.debian.org/debian-security}"
export AETHER_LOW_DISK="${AETHER_LOW_DISK:-1}"
export AETHER_CUSTOM_KERNEL="${AETHER_CUSTOM_KERNEL:-0}"
export AETHER_ALLOW_LARGE="${AETHER_ALLOW_LARGE:-0}"
export AETHER_KEEP_BUILD="${AETHER_KEEP_BUILD:-0}"
export AETHER_NO_BROWSER="${AETHER_NO_BROWSER:-0}"

# shellcheck source=scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

CHECK_ONLY=0
while (($#)); do
  case "$1" in
    --check)          CHECK_ONLY=1 ;;
    --custom-kernel)  AETHER_CUSTOM_KERNEL=1 ;;
    --no-custom-kernel) AETHER_CUSTOM_KERNEL=0 ;;
    --keep-build)     AETHER_KEEP_BUILD=1 ;;
    --allow-large)    AETHER_ALLOW_LARGE=1 ;;
    --low-disk)       AETHER_LOW_DISK=1 ;;
    --no-low-disk)    AETHER_LOW_DISK=0 ;;
    --no-browser)     AETHER_NO_BROWSER=1 ;;
    -h|--help)        usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

export AETHER_CUSTOM_KERNEL AETHER_ALLOW_LARGE AETHER_KEEP_BUILD AETHER_NO_BROWSER

main() {
  need_root
  step "AetherOS build"
  log "suite=${AETHER_SUITE} arch=${AETHER_ARCH} low_disk=${AETHER_LOW_DISK} custom_kernel=${AETHER_CUSTOM_KERNEL}"
  log "build dir: ${AETHER_BUILD}"

  mkdir -p "$AETHER_BUILD" "$AETHER_ISO_DIR" "$AETHER_OUT"

  # 00 is always run; it prepares directories and checks the host.
  bash "$ROOT_DIR/scripts/00-host-check.sh"
  if (( CHECK_ONLY )); then
    ok "host check complete"
    exit 0
  fi

  local stage
  for stage in \
    10-fetch-base.sh \
    20-configure.sh \
    30-desktop.sh \
    40-compat.sh \
    50-kernel.sh \
    60-squashfs.sh \
    70-iso.sh; do
    step "stage: $stage"
    bash "$ROOT_DIR/scripts/$stage"
    low_disk_clean
  done

  step "build complete"
  ls -lh "$AETHER_OUT"/aetheros-*.iso 2>/dev/null || true
  printf '\nWrite to USB (double-check the device!):\n'
  printf '  sudo dd if=%s/aetheros-%s-%s.iso of=/dev/sdX bs=4M status=progress oflag=sync\n\n' \
    "$AETHER_OUT" "${AETHER_VERSION:-0.1}" "$AETHER_ARCH"

  if [[ $AETHER_KEEP_BUILD != 1 ]]; then
    log "keeping build/rootfs for now; run 'sudo ./scripts/clean.sh --build' to reclaim ~4 GB"
  fi
}

main "$@"
