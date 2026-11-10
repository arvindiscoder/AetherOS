#!/usr/bin/env bash
# Stage 00: host validation and build-directory preparation.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "host check"

[[ -f /etc/debian_version ]] || die "Debian/Ubuntu host required (debootstrap + chroot). This host is not Debian-based."
need_root

# Core host tools. Keep this list aligned with docs/BUILD.md.
REQUIRED=(debootstrap mksquashfs xorriso grub-mkrescue grub-mkstandalone
          mkfs.fat sgdisk rsync zstd curl gpg chroot mountpoint findmnt
          sha256sum numfmt awk sed grep mformat)
MISSING=()
for c in "${REQUIRED[@]}"; do have "$c" || MISSING+=("$c"); done
if ((${#MISSING[@]})); then
  warn "missing host packages/commands: ${MISSING[*]}"
  cat <<'EOF'
Install on Debian/Ubuntu:
  sudo apt update
  sudo apt install -y debootstrap squashfs-tools xorriso grub-pc-bin \
    grub-efi-amd64-bin mtools dosfstools gdisk rsync zstd syslinux-utils \
    isolinux gpg curl
EOF
  die "install the missing host dependencies and re-run"
fi

# UEFI GRUB files are required for a dual BIOS/UEFI ISO.
[[ -d /usr/lib/grub/x86_64-efi ]] || die "grub-efi-amd64-bin is missing (/usr/lib/grub/x86_64-efi not found)"
[[ -d /usr/lib/grub/i386-pc ]]    || die "grub-pc-bin is missing (/usr/lib/grub/i386-pc not found)"

# Disk budget: base rootfs + apt + squashfs + ISO. 16 GB hosts are tight.
mkdir -p "$AETHER_BUILD" "$AETHER_ISO_DIR" "$AETHER_OUT"
require_free_gb "$AETHER_BUILD" 8
FREE_GB=$(( $(free_bytes "$AETHER_BUILD") / 1024 / 1024 / 1024 ))
log "free space in build filesystem: ${FREE_GB} GB"
if (( FREE_GB < 12 )); then
  warn "less than 12 GB free. Low-disk mode is enabled; avoid building Wine/Waydroid packs on this host."
fi

# CPU/RAM sanity. mksquashfs -processors is capped below to avoid OOM in a 2 GB VM.
CPUS=$(nproc)
MEM_MB=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
log "host: ${CPUS} CPUs, ${MEM_MB} MB RAM, kernel $(uname -r)"
if (( MEM_MB < 1800 )); then
  warn "host has < 1.8 GB RAM; squashfs compression will be slow and may be killed"
fi

# Network reachability (debootstrap needs it). A HEAD request is enough.
if ! curl -fsI --max-time 15 "$AETHER_MIRROR/dists/$AETHER_SUITE/Release" >/dev/null; then
  die "cannot reach $AETHER_MIRROR (check network/proxy)"
fi
ok "Debian mirror reachable"

# Clean stale mounts from an interrupted previous build.
unmount_chroot

# Detect a running container; debootstrap + mounts usually need privileges.
if [[ -f /.dockerenv ]] || [[ $(cat /proc/1/comm 2>/dev/null) == "tini" ]]; then
  warn "container-like environment detected; chroot mounts may fail. Use a full VM for builds."
fi

# Prepare the base tree, but never delete a half-built rootfs automatically.
mkdir -p "$AETHER_ROOTFS" "$AETHER_ISO_DIR/live" "$AETHER_ISO_DIR/boot/grub"
if [[ -f "$AETHER_ROOTFS/.aether-base" ]]; then
  ok "existing rootfs detected (stage 10 will reuse it)"
fi

# Marker for scripts that need to know the build contract.
cat >"$AETHER_BUILD/build.env" <<EOF
AETHER_VERSION=${AETHER_VERSION:-0.1}
AETHER_SUITE=$AETHER_SUITE
AETHER_ARCH=$AETHER_ARCH
AETHER_MIRROR=$AETHER_MIRROR
AETHER_LOW_DISK=$AETHER_LOW_DISK
AETHER_CUSTOM_KERNEL=$AETHER_CUSTOM_KERNEL
EOF
ok "host check passed"
