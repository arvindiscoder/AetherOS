#!/usr/bin/env bash
# Stage 50: kernel policy. Debian's kernel is the default; an optional
# low-latency build is available with --custom-kernel.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "kernel"

KVER=$(ls -1 "$AETHER_ROOTFS"/boot/vmlinuz-* 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1 || true)
if [[ -z "$KVER" ]]; then
  # Stage 60 strips /boot after copying the kernel to the ISO. If a later build
  # reuses that rootfs, dpkg still records the image as installed; reinstall
  # the concrete versioned package to restore /boot before rebuilding.
  KERNEL_PKG=$(chroot_run dpkg-query -W -f='${db:Status-Status} ${Package}\n' 2>/dev/null \
    | awk '$1 == "installed" && $2 ~ /^linux-image-[0-9]/ {print $2}' \
    | sort -V | tail -1)
  [[ -n "$KERNEL_PKG" ]] || die "no installed Debian kernel package found"
  log "restoring stripped kernel files from $KERNEL_PKG"
  # A previous successful build copied the exact boot artifacts here before
  # stripping /boot from its SquashFS. Prefer that cache because Debian may
  # have rotated the versioned package off the mirror while its meta package
  # remains marked installed in the reused rootfs.
  CACHED_KVER=$(basename "$(readlink "$AETHER_ROOTFS/vmlinuz" 2>/dev/null || true)" | sed 's/^vmlinuz-//')
  if [[ -n "$CACHED_KVER" && -f "$AETHER_ISO_DIR/live/vmlinuz" && -f "$AETHER_ISO_DIR/live/initrd.img" ]]; then
    install -D -m 0644 "$AETHER_ISO_DIR/live/vmlinuz" "$AETHER_ROOTFS/boot/vmlinuz-$CACHED_KVER"
    install -D -m 0644 "$AETHER_ISO_DIR/live/initrd.img" "$AETHER_ROOTFS/boot/initrd.img-$CACHED_KVER"
    ok "restored kernel and initramfs from the previous successful build"
  else
    aether_apt install --reinstall "$KERNEL_PKG" || true
    KVER=$(ls -1 "$AETHER_ROOTFS"/boot/vmlinuz-* 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1 || true)
  fi
  KVER=$(ls -1 "$AETHER_ROOTFS"/boot/vmlinuz-* 2>/dev/null | sed 's/.*vmlinuz-//' | sort -V | tail -1 || true)
fi
[[ -n "$KVER" ]] || die "no kernel installed in rootfs (linux-image-amd64 failed?)"
log "installed kernel: $KVER"

if [[ ${AETHER_CUSTOM_KERNEL} != 1 ]]; then
  # The stock Debian kernel is built with CONFIG_PREEMPT_DYNAMIC; the ISO
  # cmdline sets preempt=full. This is the right default for a 16 GB budget.
  if [[ -f "$AETHER_ROOTFS/boot/config-$KVER" ]]; then
    if grep -q '^CONFIG_PREEMPT_DYNAMIC=y' "$AETHER_ROOTFS/boot/config-$KVER"; then
      ok "Debian kernel supports preempt=full"
    else
      warn "Debian kernel lacks PREEMPT_DYNAMIC; preempt=full will be ignored"
    fi
  fi
  if ! ls -1 "$AETHER_ROOTFS"/boot/initrd.img-* >/dev/null 2>&1; then
    warn "no initramfs found; regenerating"
    chroot_run update-initramfs -u -k all
  fi
  ok "using Debian kernel (no custom compile)"
  exit 0
fi

# ---------------------------------------------------------------------------
# Optional custom kernel. This is deliberately opt-in: it takes 20-60 min,
# needs ~2.5 GB extra disk, and can fail on a memory-constrained host.
# ---------------------------------------------------------------------------
step "custom kernel build (this can take a long time)"
require_free_gb "$AETHER_BUILD" 4
aether_apt update
JOBS=${AETHER_KERNEL_JOBS:-$(nproc)}
(( JOBS > 4 )) && JOBS=4
log "jobs=${JOBS} (capped to avoid OOM on 2 GB hosts)"

aether_apt install --no-install-recommends \
  build-essential bc bison flex libssl-dev libelf-dev libncurses-dev \
  dwarves zstd cpio kmod fakeroot dpkg-dev

SOURCE_PKG=$(chroot_run bash -c "apt-cache search '^linux-source-[0-9]' | awk '{print \$1}' | sort -V | tail -1")
[[ -n "$SOURCE_PKG" ]] || die "no linux-source package found"
log "source package: $SOURCE_PKG"
aether_apt install --no-install-recommends "$SOURCE_PKG"

TARBALL=$(chroot_run bash -c "ls -1 /usr/src/linux-source-*.tar.* 2>/dev/null | sort -V | tail -1")
[[ -n "$TARBALL" ]] || die "linux-source tarball not found"

chroot_run bash -c "rm -rf /usr/src/aether-linux && mkdir -p /usr/src/aether-linux"
case "$TARBALL" in
  *.xz) chroot_run tar -xJf "$TARBALL" -C /usr/src/aether-linux --strip-components=1 ;;
  *.gz) chroot_run tar -xzf "$TARBALL" -C /usr/src/aether-linux --strip-components=1 ;;
  *) die "unknown tarball compression: $TARBALL" ;;
esac

install_file "$AETHER_ROOT/config/kernel/aetheros.fragment" \
  "$AETHER_ROOTFS/usr/src/aether-linux/aetheros.fragment"

# Base config: the installed kernel's config is the safest starting point.
BASE_CONFIG=$(chroot_run bash -c "ls -1 /boot/config-* 2>/dev/null | sort -V | tail -1")
if [[ -n "$BASE_CONFIG" ]]; then
  chroot_run cp "$BASE_CONFIG" /usr/src/aether-linux/.config
else
  warn "no /boot/config-*; starting from defconfig"
  chroot_run bash -c "cd /usr/src/aether-linux && make defconfig"
fi

chroot_run bash -c "cd /usr/src/aether-linux && \
  ./scripts/kconfig/merge_config.sh -m .config aetheros.fragment >/dev/null && \
  make olddefconfig"

# Build Debian packages (faster to install and record than raw bzImage).
# Debian's linux-source package currently carries a debhelper-compat (= 12)
# Build-Depends entry, while trixie's installed debhelper compatibility level
# is newer. The kernel build dependencies above are installed explicitly and
# dpkg reports no other missing dependencies, so skip only dpkg's metadata
# gate; the kernel's own build and package targets still run normally.
chroot_run bash -c "cd /usr/src/aether-linux && make -j${JOBS} bindeb-pkg LOCALVERSION=-aether DPKG_FLAGS=-d"

shopt -s nullglob
DEBS=("$AETHER_ROOTFS"/usr/src/linux-image-*_*.deb "$AETHER_ROOTFS"/usr/src/linux-headers-*_*.deb)
shopt -u nullglob
((${#DEBS[@]})) || die "custom kernel build produced no .deb packages"

# Install image + headers. Headers are useful for DKMS/binder modules.
for deb in "${DEBS[@]}"; do
  chroot_run dpkg -i "/usr/src/$(basename "$deb")"
done
chroot_run update-initramfs -u -k all

# Reclaim the build tree before squashfs.
chroot_run bash -c 'rm -rf /usr/src/aether-linux /usr/src/linux-source-*.tar.* \
  /usr/src/linux-image-*_*.deb /usr/src/linux-headers-*_*.deb \
  /usr/src/linux-libc-dev_*_*.deb' 2>/dev/null || true

NEWK=$(ls -1 "$AETHER_ROOTFS"/boot/vmlinuz-* | sed 's/.*vmlinuz-//' | sort -V | tail -1)
ok "custom kernel installed: $NEWK"
