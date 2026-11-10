#!/usr/bin/env bash
# Stage 20: install the core package set and configure the base system.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "installing core packages"

# Stage 10's low-disk cleanup removes /var/lib/apt/lists. Refresh before the
# package-name validation; otherwise apt-cache reports every package missing.
aether_apt update

mapfile -t WANTED < <(grep -vE '^[[:space:]]*(#|$)' "$AETHER_ROOT/config/packages.core")
if [[ ${AETHER_NO_BROWSER} == 1 ]]; then
  mapfile -t WANTED < <(printf '%s\n' "${WANTED[@]}" | grep -v '^chromium$')
  warn "AETHER_NO_BROWSER=1: Chromium omitted (ISO will be smaller, no default browser)"
fi

# Verify package names before a single apt transaction. One typo should not
# leave a half-configured system.
VALID=()
for p in "${WANTED[@]}"; do
  if chroot_run apt-cache show "$p" >/dev/null 2>&1; then
    VALID+=("$p")
  else
    warn "package not found in ${AETHER_SUITE}: $p (skipped)"
  fi
done
((${#VALID[@]})) || die "no valid packages in config/packages.core"

aether_apt install --no-install-recommends "${VALID[@]}"

# Optional packages: useful, never fatal.
aether_apt_soft fonts-jetbrains-mono intel-media-va-driver iwgtk \
  firmware-sof-signed sof-firmware gnome-keyring

# ---------------------------------------------------------------------------
# Identity, locale, time
# ---------------------------------------------------------------------------
printf 'aether\n' >"$AETHER_ROOTFS/etc/hostname"
cat >"$AETHER_ROOTFS/etc/hosts" <<'EOF'
127.0.0.1   localhost
127.0.1.1   aether
::1         localhost ip6-localhost ip6-loopback
EOF

cat >"$AETHER_ROOTFS/etc/default/locale" <<'EOF'
LANG=C.UTF-8
LANGUAGE=en_US:en
EOF
printf 'C.UTF-8 UTF-8\nen_US.UTF-8 UTF-8\n' >"$AETHER_ROOTFS/etc/locale.gen"
chroot_run locale-gen

ln -sf /usr/share/zoneinfo/UTC "$AETHER_ROOTFS/etc/localtime"
printf 'UTC\n' >"$AETHER_ROOTFS/etc/timezone"

cat >"$AETHER_ROOTFS/etc/os-release" <<'EOF'
PRETTY_NAME="AetherOS 0.1 (Nimbus)"
NAME="AetherOS"
VERSION_ID="0.1"
VERSION="0.1 (Nimbus)"
VERSION_CODENAME=trixie
ID=aetheros
ID_LIKE=debian
ANSI_COLOR="0;36"
HOME_URL="https://example.invalid/aetheros"
SUPPORT_URL="https://example.invalid/aetheros/docs"
BUG_REPORT_URL="https://example.invalid/aetheros/issues"
DEBIAN_CODENAME=trixie
EOF
cat >"$AETHER_ROOTFS/etc/issue" <<'EOF'
AetherOS 0.1 (Nimbus) \n \l
EOF
cat >"$AETHER_ROOTFS/etc/motd" <<'EOF'
  AetherOS 0.1 "Nimbus"  ·  labwc / Wayland
  Super+Return terminal   Super+D launcher   Super+Space Astra
  Install: sudo aether-install   Packs: aether-pack list
EOF

# ---------------------------------------------------------------------------
# The single live user
# ---------------------------------------------------------------------------
# Create every supplementary group the live user needs before useradd. Debian
# minbase does not guarantee that all of these exist, and useradd fails the
# whole build if one is missing.
for g in audio video render input users netdev plugdev bluetooth; do
  chroot_run groupadd -f "$g" >/dev/null 2>&1 || true
done
if ! chroot_run id aether >/dev/null 2>&1; then
  chroot_run useradd -m -u 1000 -s /bin/bash -G audio,video,render,input,users,netdev,plugdev,bluetooth aether
else
  chroot_run usermod -aG audio,video,render,input,users,netdev,plugdev,bluetooth aether >/dev/null 2>&1 || true
fi
# Live session: no password. The installer replaces this with a real password.
chroot_run passwd -d aether >/dev/null

install -d -m 0750 "$AETHER_ROOTFS/etc/sudoers.d"
cat >"$AETHER_ROOTFS/etc/sudoers.d/90-aether-live" <<'EOF'
# LIVE IMAGE ONLY. aether-install removes this file on the target system.
aether ALL=(ALL) NOPASSWD: ALL
EOF
chmod 0440 "$AETHER_ROOTFS/etc/sudoers.d/90-aether-live"
chroot_run visudo -cf /etc/sudoers >/dev/null

# Autologin on tty1; .bash_profile starts labwc.
install -d -m 0755 "$AETHER_ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat >"$AETHER_ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin aether --noclear %I $TERM
EOF

cat >"$AETHER_ROOTFS/etc/skel/.bash_profile" <<'EOF'
# AetherOS: start the Wayland session on the first VT after autologin.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
  exec labwc
fi
EOF
cp "$AETHER_ROOTFS/etc/skel/.bash_profile" "$AETHER_ROOTFS/home/aether/.bash_profile"
chown 1000:1000 "$AETHER_ROOTFS/home/aether/.bash_profile"

# ---------------------------------------------------------------------------
# Overlay payload (helpers, installer, firstboot)
# ---------------------------------------------------------------------------
copy_tree "$AETHER_ROOT/overlay/usr/local" "$AETHER_ROOTFS/usr/local"
install_file "$AETHER_ROOT/installer/aether-install" "$AETHER_ROOTFS/usr/local/sbin/aether-install" 0755
find "$AETHER_ROOTFS/usr/local" -type f \( -path '*/bin/*' -o -path '*/sbin/*' \) -exec chmod 0755 {} +
copy_tree "$AETHER_ROOT/overlay/etc" "$AETHER_ROOTFS/etc"
copy_tree "$AETHER_ROOT/overlay/usr/share" "$AETHER_ROOTFS/usr/share"

# Keep the user-facing docs on the live image. They live outside /usr/share/doc
# so the stage-60 documentation strip does not remove them.
install -d -m 0755 "$AETHER_ROOTFS/usr/share/aether/docs"
cp -a "$AETHER_ROOT/docs/." "$AETHER_ROOTFS/usr/share/aether/docs/"
install -m 0644 "$AETHER_ROOT/README.md" "$AETHER_ROOTFS/usr/share/aether/docs/README.md"

# ---------------------------------------------------------------------------
# System tuning files
# ---------------------------------------------------------------------------
install_file "$AETHER_ROOT/config/system/sysctl/90-aether.conf" "$AETHER_ROOTFS/etc/sysctl.d/90-aether.conf"
install_file "$AETHER_ROOT/config/system/zram-generator.conf" "$AETHER_ROOTFS/etc/systemd/zram-generator.conf"
install_file "$AETHER_ROOT/config/system/journald.conf" "$AETHER_ROOTFS/etc/systemd/journald.conf"
install_file "$AETHER_ROOT/config/system/earlyoom" "$AETHER_ROOTFS/etc/default/earlyoom"
install_file "$AETHER_ROOT/config/system/limits.conf" "$AETHER_ROOTFS/etc/security/limits.d/90-aether.conf"
install_file "$AETHER_ROOT/config/system/system.conf" "$AETHER_ROOTFS/etc/systemd/system.conf.d/99-aether.conf"
install_file "$AETHER_ROOT/config/system/logind.conf" "$AETHER_ROOTFS/etc/systemd/logind.conf.d/99-aether.conf"
install_file "$AETHER_ROOT/config/system/udev/60-aether-io.rules" "$AETHER_ROOTFS/etc/udev/rules.d/60-aether-io.rules"
install_file "$AETHER_ROOT/config/system/tmpfiles.conf" "$AETHER_ROOTFS/etc/tmpfiles.d/aether.conf"

# Network: iwd owns Wi-Fi association; systemd-networkd owns addressing/DHCP.
install -d -m 0755 "$AETHER_ROOTFS/etc/systemd/network" "$AETHER_ROOTFS/etc/iwd"
# live-boot's initramfs writes a temporary interfaces file under /root/etc/network
# while configuring the live session, even though the installed system uses
# systemd-networkd. Preserve the directory so early boot can continue.
install -d -m 0755 "$AETHER_ROOTFS/etc/network"
cat >"$AETHER_ROOTFS/etc/iwd/main.conf" <<'EOF'
[General]
EnableNetworkConfiguration=false
AddressRandomization=once
AddressRandomizationRange=full

[Network]
NameResolvingService=systemd
EOF
cat >"$AETHER_ROOTFS/etc/systemd/network/20-wireless.network" <<'EOF'
[Match]
Name=wl* wlan*
[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF
cat >"$AETHER_ROOTFS/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*
[Network]
DHCP=yes
IPv6AcceptRA=yes
EOF
ln -sfn /run/systemd/resolve/stub-resolv.conf "$AETHER_ROOTFS/etc/resolv.conf"

# tmpfs for /tmp keeps eMMC writes down.
cat >"$AETHER_ROOTFS/etc/fstab" <<'EOF'
# AetherOS: the root filesystem is assembled by live-boot.
# aether-install rewrites this file for the target disk.
tmpfs  /tmp  tmpfs  defaults,nosuid,nodev,noatime,size=512M  0 0
EOF

# First boot performs machine-id and cache setup.
install -d -m 0755 "$AETHER_ROOTFS/var/lib/aether"
# Keep this file empty but writable. systemd and aether-firstboot generate the
# real ID on first boot; a read-only empty file can prevent that.
: >"$AETHER_ROOTFS/etc/machine-id"
chmod 0644 "$AETHER_ROOTFS/etc/machine-id"

# ---------------------------------------------------------------------------
# Service policy: keep the idle set tiny.
# ---------------------------------------------------------------------------
chroot_run systemctl set-default graphical.target
chroot_run systemctl enable systemd-networkd systemd-resolved iwd systemd-timesyncd aether-firstboot.service >/dev/null
chroot_run systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service >/dev/null 2>&1 || true
# Bluetooth controller support (headphones, keyboards, mice).
chroot_run systemctl enable bluetooth.service >/dev/null 2>&1 || true

# Auto-switch the default audio sink/source to newly connected devices such as
# Bluetooth headphones (JLab Go Pods ANC). PipeWire ships this module disabled.
if [[ -f "$AETHER_ROOTFS/usr/share/pipewire/pipewire-pulse.conf" ]]; then
  sed -i 's/^    #{ cmd = "load-module" args = "module-switch-on-connect" }/    { cmd = "load-module" args = "module-switch-on-connect" }/' \
    "$AETHER_ROOTFS/usr/share/pipewire/pipewire-pulse.conf" || true
fi

# Mask things that are either irrelevant on this image or wake up the CPU.
chroot_run systemctl mask \
  apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer \
  man-db.service man-db.timer e2scrub_all.timer e2scrub_reap.service \
  logrotate.timer dpkg-db-backup.timer motd-news.timer \
  systemd-oomd.service >/dev/null 2>&1 || true

# journald is volatile: no writes to eMMC, no 100 MB journal.
install -d -m 0755 "$AETHER_ROOTFS/var/log/journal" 2>/dev/null || true

# Disable APT's background timers in the installed system too.
cat >"$AETHER_ROOTFS/etc/apt/apt.conf.d/99-aether-periodic" <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF

# Colorful, fast console; harmless on Chromebooks and VirtualBox.
cat >"$AETHER_ROOTFS/etc/default/console-setup" <<'EOF'
CHARMAP="UTF-8"
CODESET="Lat15"
FONTFACE="Terminus"
FONTSIZE="8x16"
EOF

# ---------------------------------------------------------------------------
# Initramfs: universal hardware, ZSTD, VirtualBox/Chromebook storage drivers.
# ---------------------------------------------------------------------------
cat >"$AETHER_ROOTFS/etc/initramfs-tools/initramfs.conf" <<'EOF'
MODULES=most
BUSYBOX=auto
COMPRESS=zstd
COMPRESSLEVEL=19
DEVICE=eth0
NFSROOT=auto
RUN_SSH=no
EOF
cat >"$AETHER_ROOTFS/etc/initramfs-tools/modules" <<'EOF'
# Storage / virtual machines
ahci
sd_mod
uas
usb_storage
virtio_blk
virtio_scsi
virtio_pci
virtio_gpu
vmw_pvscsi
vmwgfx
vboxvideo
vboxguest
# Filesystems
squashfs
overlay
ext4
vfat
# Input
hid_generic
usbhid
i2c_hid
i2c_hid_acpi
EOF
chroot_run update-initramfs -u -k all

low_disk_clean
ok "base configured"
