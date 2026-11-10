#!/usr/bin/env bash
# Stage 30: desktop environment, theme, browser, assistant.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "installing labwc desktop"

install -d -m 0755 \
  "$AETHER_ROOTFS/etc/xdg/labwc" \
  "$AETHER_ROOTFS/etc/xdg/waybar" \
  "$AETHER_ROOTFS/etc/xdg/foot" \
  "$AETHER_ROOTFS/etc/xdg/fuzzel" \
  "$AETHER_ROOTFS/etc/xdg/mako" \
  "$AETHER_ROOTFS/etc/gtk-3.0" \
  "$AETHER_ROOTFS/etc/gtk-4.0" \
  "$AETHER_ROOTFS/usr/share/themes/aether-glass/openbox-3" \
  "$AETHER_ROOTFS/usr/share/aether/astra" \
  "$AETHER_ROOTFS/usr/share/backgrounds/aether" \
  "$AETHER_ROOTFS/usr/share/applications" \
  "$AETHER_ROOTFS/usr/share/aether" \
  "$AETHER_ROOTFS/etc/chromium/policies/managed" \
  "$AETHER_ROOTFS/home/aether/.config/environment.d"

# --- compositor -------------------------------------------------------------
install_file "$AETHER_ROOT/config/desktop/labwc/rc.xml"       "$AETHER_ROOTFS/etc/xdg/labwc/rc.xml"
install_file "$AETHER_ROOT/config/desktop/labwc/menu.xml"     "$AETHER_ROOTFS/etc/xdg/labwc/menu.xml"
install_file "$AETHER_ROOT/config/desktop/labwc/autostart"    "$AETHER_ROOTFS/etc/xdg/labwc/autostart"
install_file "$AETHER_ROOT/config/desktop/labwc/environment"  "$AETHER_ROOTFS/etc/xdg/labwc/environment"
install_file "$AETHER_ROOT/config/desktop/labwc/themerc"      "$AETHER_ROOTFS/usr/share/themes/aether-glass/openbox-3/themerc"
chmod 0755 "$AETHER_ROOTFS/etc/xdg/labwc/autostart"

# --- panel / terminal / launcher / notifications ---------------------------
install_file "$AETHER_ROOT/config/desktop/waybar/config.jsonc" "$AETHER_ROOTFS/etc/xdg/waybar/config.jsonc"
install_file "$AETHER_ROOT/config/desktop/waybar/dock.jsonc"   "$AETHER_ROOTFS/etc/xdg/waybar/dock.jsonc"
install_file "$AETHER_ROOT/config/desktop/waybar/style.css"    "$AETHER_ROOTFS/etc/xdg/waybar/style.css"
install_file "$AETHER_ROOT/config/desktop/foot/foot.ini"       "$AETHER_ROOTFS/etc/xdg/foot/foot.ini"
install_file "$AETHER_ROOT/config/desktop/fuzzel/fuzzel.ini"   "$AETHER_ROOTFS/etc/xdg/fuzzel/fuzzel.ini"
install_file "$AETHER_ROOT/config/desktop/mako/config"         "$AETHER_ROOTFS/etc/xdg/mako/config"

# --- wallpaper --------------------------------------------------------------
# swaybg reliably loads PNG on every build; SVG is kept as a fallback for
# systems where rsvg-convert was unavailable.
install_file "$AETHER_ROOT/overlay/usr/share/backgrounds/aether/liquid-glass.svg" \
  "$AETHER_ROOTFS/usr/share/backgrounds/aether/liquid-glass.svg"
if chroot_run rsvg-convert -w 1920 -h 1080 \
    -o /usr/share/backgrounds/aether/liquid-glass.png \
    /usr/share/backgrounds/aether/liquid-glass.svg >/dev/null 2>&1; then
  ok "wallpaper converted to PNG"
else
  warn "rsvg-convert unavailable; swaybg will use the SVG fallback"
fi

# --- GTK (system-wide; applies to pcmanfm, zenity, GTK apps) ----------------
install_file "$AETHER_ROOT/config/desktop/gtk-3.0/gtk.css" "$AETHER_ROOTFS/etc/gtk-3.0/gtk.css"
install_file "$AETHER_ROOT/config/desktop/gtk-4.0/gtk.css" "$AETHER_ROOTFS/etc/gtk-4.0/gtk.css"

# --- user session defaults --------------------------------------------------
cat >"$AETHER_ROOTFS/home/aether/.config/environment.d/90-aether.conf" <<'EOF'
XDG_CURRENT_DESKTOP=labwc
QT_QPA_PLATFORM=wayland
GDK_BACKEND=wayland,x11
MOZ_ENABLE_WAYLAND=1
# VirtualBox's hardware cursor plane can lag behind pointer motion.
WLR_NO_HARDWARE_CURSORS=1
EOF
chown -R 1000:1000 "$AETHER_ROOTFS/home/aether/.config"

# --- Astra extension + Chromium policy -------------------------------------
copy_tree "$AETHER_ROOT/config/desktop/chromium/aether-astra" "$AETHER_ROOTFS/usr/share/aether/astra"
install_file "$AETHER_ROOT/overlay/etc/chromium/policies/managed/aether.json" \
  "$AETHER_ROOTFS/etc/chromium/policies/managed/aether.json"
cat >"$AETHER_ROOTFS/etc/chromium/default" <<'EOF'
# Read by Debian's /usr/bin/chromium wrapper. The aether-browser wrapper adds
# the Astra extension and a Wayland/X11 platform choice at runtime.
CHROMIUM_FLAGS="--enable-low-end-device-mode --renderer-process-limit=3 --process-per-site --password-store=basic --no-first-run --no-default-browser-check"
EOF

# --- desktop entries --------------------------------------------------------
cat >"$AETHER_ROOTFS/usr/share/applications/aether-browser.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Aether Browser
GenericName=Web Browser
Comment=Chromium with the Aether Astra assistant extension
Exec=aether-browser %U
TryExec=aether-browser
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;application/xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/ftp;
StartupNotify=true
StartupWMClass=Chromium
EOF
cat >"$AETHER_ROOTFS/usr/share/applications/aether-assistant.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Astra Assistant
Comment=ChatGPT / assistant bridge (Super+Space)
Exec=aether-assistant
Icon=system-search
Terminal=false
Categories=Utility;
StartupWMClass=AetherAstra
EOF
cat >"$AETHER_ROOTFS/usr/share/applications/aether-install.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Install AetherOS
Comment=Install to disk (full or frugal)
Exec=foot -e sudo aether-install
Icon=system-software-install
Terminal=false
Categories=System;
EOF
cat >"$AETHER_ROOTFS/usr/share/applications/aether-packs.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Compatibility Packs
Comment=Install optional Wine, Waydroid, and media runtimes
Exec=aether-pack-manager
Icon=applications-system
Terminal=false
Categories=System;Settings;
EOF

# --- fonts, icons, mime caches (rebuilt again on first boot) ----------------
chroot_run bash -c 'fc-cache -f >/dev/null 2>&1 || true'
chroot_run bash -c 'gtk-update-icon-cache -f -t /usr/share/icons/Adwaita >/dev/null 2>&1 || true'
chroot_run update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
chroot_run update-mime-database /usr/share/mime >/dev/null 2>&1 || true

# --- user skeleton ----------------------------------------------------------
install -d -m 0755 "$AETHER_ROOTFS/etc/skel/.config/environment.d"
cp -a "$AETHER_ROOTFS/home/aether/.config/environment.d/90-aether.conf" \
      "$AETHER_ROOTFS/etc/skel/.config/environment.d/90-aether.conf"
cp -a "$AETHER_ROOTFS/etc/skel/." "$AETHER_ROOTFS/home/aether/"
chown -R 1000:1000 "$AETHER_ROOTFS/home/aether"

ok "desktop installed"
