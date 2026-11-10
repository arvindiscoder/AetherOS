#!/usr/bin/env bash
# Stage 10: create the Debian trixie minbase and make it buildable.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

step "fetching Debian ${AETHER_SUITE} minbase"

if [[ -f "$AETHER_ROOTFS/.aether-base" ]]; then
  ok "rootfs already bootstrapped; reusing"
else
  rm -rf "$AETHER_ROOTFS"
  mkdir -p "$AETHER_ROOTFS"
  debootstrap \
    --variant=minbase \
    --arch="$AETHER_ARCH" \
    --components=main,contrib,non-free-firmware \
    --include=ca-certificates,curl,gnupg,apt-transport-https,locales,tzdata \
    "$AETHER_SUITE" "$AETHER_ROOTFS" "$AETHER_MIRROR"
  touch "$AETHER_ROOTFS/.aether-base"
fi

# --- apt configuration -----------------------------------------------------
cat >"$AETHER_ROOTFS/etc/apt/sources.list" <<EOF
deb ${AETHER_MIRROR} ${AETHER_SUITE} main contrib non-free-firmware
deb ${AETHER_MIRROR} ${AETHER_SUITE}-updates main contrib non-free-firmware
deb ${AETHER_SECURITY} ${AETHER_SUITE}-security main contrib non-free-firmware
EOF
rm -f "$AETHER_ROOTFS"/etc/apt/sources.list.d/*.list \
      "$AETHER_ROOTFS"/etc/apt/sources.list.d/*.sources 2>/dev/null || true

cat >"$AETHER_ROOTFS/etc/apt/apt.conf.d/99-aether" <<'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
APT::Get::Assume-Yes "true";
Acquire::Languages "none";
Acquire::Retries "3";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
EOF

# Drop documentation and non-English locales at install time. Copyright files
# are kept because licenses must remain available.
cat >"$AETHER_ROOTFS/etc/dpkg/dpkg.cfg.d/99-aether-trim" <<'EOF'
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/man/*
path-exclude=/usr/share/info/*
path-exclude=/usr/share/lintian/*
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/en*
path-include=/usr/share/locale/locale.alias
path-exclude=/usr/share/bash-completion/completions/*
EOF

# --- chroot mounts ---------------------------------------------------------
mkdir -p "$AETHER_ROOTFS"/{proc,sys,dev,dev/pts,run,tmp}
mount -t proc proc "$AETHER_ROOTFS/proc"
mount -t sysfs sysfs "$AETHER_ROOTFS/sys"
mount --bind /dev "$AETHER_ROOTFS/dev"
mount --bind /dev/pts "$AETHER_ROOTFS/dev/pts"
mount -t tmpfs -o nosuid,nodev,size=64M tmpfs "$AETHER_ROOTFS/run" 2>/dev/null || true
chmod 1777 "$AETHER_ROOTFS/tmp"

# DNS for the chroot. The live image gets a systemd-resolved symlink later.
# Remove a stale symlink first so re-running stage 10 cannot make cp compare
# the host and target resolv.conf as the same file.
rm -f "$AETHER_ROOTFS/etc/resolv.conf"
cp -L /etc/resolv.conf "$AETHER_ROOTFS/etc/resolv.conf"

aether_apt update
aether_apt install --no-install-recommends \
  ca-certificates curl gnupg apt-transport-https locales tzdata \
  systemd-sysv systemd-timesyncd dbus dbus-user-session udev kmod initramfs-tools \
  live-boot live-boot-initramfs-tools linux-image-amd64 \
  sudo rsync nano less iproute2 iputils-ping procps psmisc util-linux \
  e2fsprogs dosfstools gdisk parted file xz-utils zstd squashfs-tools \
  python3 jq

# Keep the chroot's resolv.conf from being clobbered by package scripts.
rm -f "$AETHER_ROOTFS/etc/resolv.conf"
cp -L /etc/resolv.conf "$AETHER_ROOTFS/etc/resolv.conf"

low_disk_clean
ok "minbase ready ($(human "$(dir_size "$AETHER_ROOTFS")"))"
