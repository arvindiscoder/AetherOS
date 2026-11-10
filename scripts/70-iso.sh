#!/usr/bin/env bash
# Stage 70: assemble a hybrid BIOS/UEFI GRUB ISO and enforce the size budget.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "building hybrid ISO"

[[ -f "$AETHER_ISO_DIR/live/vmlinuz" ]] || die "missing /live/vmlinuz"
[[ -f "$AETHER_ISO_DIR/live/initrd.img" ]] || die "missing /live/initrd.img"
[[ -f "$AETHER_ISO_DIR/live/filesystem.squashfs" ]] || die "missing SquashFS"

# --- ISO metadata -----------------------------------------------------------
install -D -m 0644 "$AETHER_ROOT/config/boot/grub.cfg" "$AETHER_ISO_DIR/boot/grub/grub.cfg"
install -d -m 0755 "$AETHER_ISO_DIR/.disk"

cat >"$AETHER_ISO_DIR/.disk/info" <<EOF
AetherOS ${AETHER_VERSION:-0.1} "Nimbus" - ${AETHER_ARCH}
Built $(date -u +%Y-%m-%dT%H:%M:%SZ)
Debian ${AETHER_SUITE} base / labwc / Liquid Glass
EOF

cat >"$AETHER_ISO_DIR/README.txt" <<'EOF'
AetherOS — hyper-lightweight Debian/Wayland live image

Live login:  user "aether", no password, passwordless sudo
Install:     sudo aether-install
Packs:       aether-pack list
Docs:        /usr/share/aether/docs (on the live system)

Boot in VirtualBox: EFI on, VMSVGA, 128 MB VRAM, 3D acceleration, 2 GB RAM.
On a Chromebook, use MrChromebox UEFI firmware and a USB written with dd/Ventoy.

The iOS runtime is not included; .ipa files are inspection-only. See the
compatibility documentation before expecting .exe/.dmg/.apk support.
EOF

# --- build ISO --------------------------------------------------------------
ISO="$AETHER_OUT/aetheros-${AETHER_VERSION:-0.1}-${AETHER_ARCH}.iso"
LOG="$AETHER_BUILD/grub-mkrescue.log"
rm -f "$ISO"

if ! grub-mkrescue -o "$ISO" "$AETHER_ISO_DIR" -- -volid AETHEROS >"$LOG" 2>&1; then
  # Very old xorriso versions reject -volid. The label is cosmetic; retry
  # without it rather than failing a valid image for a metadata nicety.
  warn "grub-mkrescue -volid failed; retrying without a custom volume label"
  rm -f "$ISO"
  if ! grub-mkrescue -o "$ISO" "$AETHER_ISO_DIR" >>"$LOG" 2>&1; then
    tail -40 "$LOG" >&2 || true
    die "grub-mkrescue failed (see $LOG)"
  fi
fi

ISO_BYTES=$(stat -c%s "$ISO")
ISO_MB=$(( ISO_BYTES / 1024 / 1024 ))
SQUASH_BYTES=$(stat -c%s "$AETHER_ISO_DIR/live/filesystem.squashfs")
KERNEL_BYTES=$(stat -c%s "$AETHER_ISO_DIR/live/vmlinuz")
INITRD_BYTES=$(stat -c%s "$AETHER_ISO_DIR/live/initrd.img")

log "ISO size: $(human "$ISO_BYTES") (${ISO_MB} MB)"
log "  squashfs: $(human "$SQUASH_BYTES")"
log "  vmlinuz:  $(human "$KERNEL_BYTES")"
log "  initrd:   $(human "$INITRD_BYTES")"

HARD_LIMIT=$(( 512 * 1024 * 1024 ))
if (( ISO_BYTES > HARD_LIMIT )); then
  if [[ ${AETHER_ALLOW_LARGE} == 1 ]]; then
    warn "ISO exceeds the 512 MB target; continuing because --allow-large was set."
  else
    warn "ISO exceeds the 512 MB hard budget."
    warn "Options: rebuild with --no-browser, remove a pack, or use --allow-large explicitly."
    die "refusing to declare a >512 MB core image complete"
  fi
fi

# --- integrity + bootability report ----------------------------------------
sha256sum "$ISO" >"$ISO.sha256"
ok "checksum: $ISO.sha256"

if command -v xorriso >/dev/null 2>&1; then
  {
    echo "== El Torito / EFI =="
    xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null || true
    echo
    echo "== files =="
    xorriso -indev "$ISO" -find /live -type f -exec lsdl 2>/dev/null || true
  } >"$AETHER_OUT/aetheros-${AETHER_VERSION:-0.1}-${AETHER_ARCH}-boot.txt"
fi

# A quick structural check: both BIOS and UEFI images must be present.
if command -v xorriso >/dev/null 2>&1; then
  if xorriso -indev "$ISO" -report_el_torito plain 2>/dev/null | grep -qi 'efi'; then
    ok "UEFI El Torito image present"
  else
    warn "could not confirm a UEFI image; test in VirtualBox with EFI enabled"
  fi
fi

step "done"
printf '\nTest in QEMU (optional):\n'
printf '  qemu-system-x86_64 -m 2048 -smp 2 -enable-kvm \\\n'
printf '    -drive file=%s,format=raw,if=virtio -vga std -boot d\n\n' "$ISO"
printf 'VirtualBox: see docs/VIRTUALBOX.md (exact 16 GB settings).\n'
printf 'USB: sudo dd if=%s of=/dev/sdX bs=4M status=progress oflag=sync\n\n' "$ISO"
