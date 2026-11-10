#!/usr/bin/env bash
# Stage 40: MIME integration, Wine registry, Waydroid bridge.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "installing compatibility integration"

install -d -m 0755 \
  "$AETHER_ROOTFS/usr/share/mime/packages" \
  "$AETHER_ROOTFS/usr/share/aether/wine" \
  "$AETHER_ROOTFS/usr/share/aether/waydroid" \
  "$AETHER_ROOTFS/etc/xdg" \
  "$AETHER_ROOTFS/home/aether/.config" \
  "$AETHER_ROOTFS/home/aether/.local/share/aether/wine"

# --- shared MIME types ------------------------------------------------------
install_file "$AETHER_ROOT/config/compat/mime/aether-compat.xml" \
  "$AETHER_ROOTFS/usr/share/mime/packages/aether-compat.xml"

# --- Wine defaults ----------------------------------------------------------
install_file "$AETHER_ROOT/config/compat/wine/aether.reg" \
  "$AETHER_ROOTFS/usr/share/aether/wine/aether.reg"

# --- Waydroid reference config ---------------------------------------------
install_file "$AETHER_ROOT/config/compat/waydroid/waydroid.cfg" \
  "$AETHER_ROOTFS/usr/share/aether/waydroid/waydroid.cfg.sample"

# --- handler desktop entries ------------------------------------------------
install -d -m 0755 "$AETHER_ROOTFS/usr/share/applications"
for f in aether-exe.desktop aether-dmg.desktop aether-apk.desktop \
         aether-ipa.desktop aether-deb.desktop aether-install-roblox.desktop; do
  install_file "$AETHER_ROOT/overlay/usr/share/applications/$f" \
    "$AETHER_ROOTFS/usr/share/applications/$f"
done

# --- default applications ---------------------------------------------------
install_file "$AETHER_ROOT/overlay/etc/xdg/mimeapps.list" \
  "$AETHER_ROOTFS/etc/xdg/mimeapps.list"
install_file "$AETHER_ROOT/overlay/etc/xdg/mimeapps.list" \
  "$AETHER_ROOTFS/home/aether/.config/mimeapps.list"
install -d -m 0755 "$AETHER_ROOTFS/etc/skel/.config"
install_file "$AETHER_ROOT/overlay/etc/xdg/mimeapps.list" \
  "$AETHER_ROOTFS/etc/skel/.config/mimeapps.list"

# --- helper permissions -----------------------------------------------------
chmod 0755 "$AETHER_ROOTFS"/usr/local/bin/aether-* \
           "$AETHER_ROOTFS"/usr/local/sbin/aether-* 2>/dev/null || true
chmod 0755 "$AETHER_ROOTFS"/usr/local/lib/aether/packs/* 2>/dev/null || true
chmod 0644 "$AETHER_ROOTFS/usr/local/lib/aether/common.sh"

# --- databases --------------------------------------------------------------
# These packages are part of the core set, but keep the build resilient if a
# mirror or optional package set changed.
chroot_run update-mime-database /usr/share/mime >/dev/null 2>&1 || true
chroot_run update-desktop-database /usr/share/applications >/dev/null 2>&1 || true

chown -R 1000:1000 "$AETHER_ROOTFS/home/aether/.config" \
                    "$AETHER_ROOTFS/home/aether/.local"

ok "MIME + compatibility wiring installed"
ok "Wine/Waydroid are NOT installed in the core image; use aether-pack"
