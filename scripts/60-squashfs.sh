#!/usr/bin/env bash
# Stage 60: strip the rootfs and build the ZSTD SquashFS.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "building SquashFS"

# --- copy boot artifacts out of the rootfs before stripping /boot ----------
KERNEL=$(ls -1 "$AETHER_ROOTFS"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1 || true)
[[ -n "$KERNEL" ]] || die "no kernel in rootfs"
KVER=${KERNEL##*/vmlinuz-}
INITRD="$AETHER_ROOTFS/boot/initrd.img-$KVER"
[[ -f "$INITRD" ]] || INITRD=$(ls -1 "$AETHER_ROOTFS"/boot/initrd.img-* 2>/dev/null | sort -V | tail -1 || true)
[[ -f "$INITRD" ]] || die "no initramfs in rootfs"

install -D -m 0644 "$KERNEL" "$AETHER_ISO_DIR/live/vmlinuz"
install -D -m 0644 "$INITRD" "$AETHER_ISO_DIR/live/initrd.img"
ok "kernel: $(basename "$KERNEL") ($(human "$(stat -c%s "$KERNEL")"))"
ok "initrd: $(basename "$INITRD") ($(human "$(stat -c%s "$INITRD")"))"

# --- trim ------------------------------------------------------------------
step "stripping documentation, caches, and non-English locales"

# Keep copyright files: they are the license notices. Remove the rest of doc.
find "$AETHER_ROOTFS/usr/share/doc" -type f ! -name copyright -delete 2>/dev/null || true
find "$AETHER_ROOTFS/usr/share/doc" -type d -empty -delete 2>/dev/null || true
rm -rf "$AETHER_ROOTFS"/usr/share/man/* \
       "$AETHER_ROOTFS"/usr/share/info/* \
       "$AETHER_ROOTFS"/usr/share/lintian/* \
       "$AETHER_ROOTFS"/usr/include/* \
       "$AETHER_ROOTFS"/usr/src/* 2>/dev/null || true

find "$AETHER_ROOTFS/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
  ! -name 'en' ! -name 'en_*' -exec rm -rf {} + 2>/dev/null || true

# Chromium ships ~50 locale .pak files. Keep only English.
if [[ -d "$AETHER_ROOTFS/usr/lib/chromium/locales" ]]; then
  find "$AETHER_ROOTFS/usr/lib/chromium/locales" -maxdepth 1 -type f \
    ! -name 'en-US.pak' ! -name 'en-GB.pak' -delete 2>/dev/null || true
fi

# Static libraries and headers are build-time only for this image.
find "$AETHER_ROOTFS/usr/lib" -type f -name '*.a' -delete 2>/dev/null || true
rm -rf "$AETHER_ROOTFS"/var/cache/apt/archives/* \
       "$AETHER_ROOTFS"/var/cache/apt/archives/partial/* \
       "$AETHER_ROOTFS"/var/lib/apt/lists/* \
       "$AETHER_ROOTFS"/var/lib/apt/lists/partial/* \
       "$AETHER_ROOTFS"/var/log/* \
       "$AETHER_ROOTFS"/tmp/* \
       "$AETHER_ROOTFS"/var/tmp/* \
       "$AETHER_ROOTFS"/root/.cache \
       "$AETHER_ROOTFS"/home/aether/.cache 2>/dev/null || true

# Runtime module trees stay; build/source links do not.
find "$AETHER_ROOTFS/lib/modules" -maxdepth 2 \( -name build -o -name source \) \
  -exec rm -f {} + 2>/dev/null || true

# The live kernel/initrd live on the ISO, not inside the squashfs.
rm -rf "$AETHER_ROOTFS"/boot/*

# Drop the apt/dpkg artifacts that only make sense on a build host.
rm -rf "$AETHER_ROOTFS"/var/lib/dpkg/updates/* 2>/dev/null || true

# Build identity, useful inside the live session and for bug reports.
cat >"$AETHER_ROOTFS/etc/aether-build" <<EOF
AETHER_VERSION=${AETHER_VERSION:-0.1}
AETHER_ARCH=${AETHER_ARCH}
AETHER_SUITE=${AETHER_SUITE}
AETHER_KERNEL=${KVER}
AETHER_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# --- unmount before mksquashfs ---------------------------------------------
unmount_chroot

step "compressing rootfs with zstd"
JOBS=$(nproc)
(( JOBS > 4 )) && JOBS=4
rm -f "$AETHER_ISO_DIR/live/filesystem.squashfs"

# Keep empty mount-point directories in the SquashFS. live-boot moves the
# initramfs virtual filesystems into these paths; excluding them entirely
# makes /root/dev (and the other mount points) disappear after the root
# filesystem is mounted.
for d in proc sys dev run tmp; do
  find "$AETHER_ROOTFS/$d" -mindepth 1 -delete 2>/dev/null || true
  mkdir -p "$AETHER_ROOTFS/$d"
done

if ! mksquashfs "$AETHER_ROOTFS" "$AETHER_ISO_DIR/live/filesystem.squashfs" \
    -comp zstd -Xcompression-level 19 -b 1M -noappend -mem 512M \
    -processors "$JOBS" \
    >"$AETHER_BUILD/squashfs.log" 2>&1; then
  tail -30 "$AETHER_BUILD/squashfs.log" >&2 || true
  die "mksquashfs failed"
fi

SQUASH="$AETHER_ISO_DIR/live/filesystem.squashfs"
SQUASH_BYTES=$(stat -c%s "$SQUASH")
SQUASH_MB=$(( SQUASH_BYTES / 1024 / 1024 ))
log "squashfs: $(human "$SQUASH_BYTES") (${SQUASH_MB} MB), zstd -19, 1M blocks"

LIMIT=${AETHER_SQUASHFS_LIMIT_MB:-400}
if (( SQUASH_MB > LIMIT )); then
  warn "SquashFS is ${SQUASH_MB} MB, above the ${LIMIT} MB soft budget."
  warn "The ISO has a 512 MB hard cap; build with --no-browser or trim more if it overflows."
fi

# --- manifest ---------------------------------------------------------------
MANIFEST="$AETHER_OUT/aetheros-${AETHER_VERSION:-0.1}-${AETHER_ARCH}.manifest.txt"
{
  echo "AetherOS ${AETHER_VERSION:-0.1} (${AETHER_ARCH}) build manifest"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel: ${KVER}"
  echo "squashfs_bytes: ${SQUASH_BYTES}"
  echo "squashfs_sha256: $(sha256sum "$SQUASH" | awk '{print $1}')"
  echo
  echo "== packages =="
  dpkg-query --admindir="$AETHER_ROOTFS/var/lib/dpkg" \
    -W -f='${Package}\t${Version}\n' 2>/dev/null || true
} >"$MANIFEST"

ok "squashfs built; manifest: $(basename "$MANIFEST")"
