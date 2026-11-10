# Architecture

## Boot chain (live ISO)

```
UEFI firmware ──> EFI/BOOT/BOOTX64.EFI ─┐
                                        ├─> GRUB2 (config/boot/grub.cfg)
legacy BIOS ────> El Torito / boot.img ─┘
                                              │
                                              ▼
                         /live/vmlinuz  +  /live/initrd.img
                         boot=live live-media-path=/live
                                              │
                                              ▼
                         live-boot mounts /live/filesystem.squashfs
                         and creates a writable overlay (tmpfs by default)
                                              │
                                              ▼
                         systemd → graphical.target
                                              │
                         getty@tty1 autologin (live only)
                                              │
                         ~/.bash_profile → labwc → autostart
                                              │
              swaybg · waybar · mako · xdg-desktop-portal-wlr · swayidle
```

The ISO is assembled with `grub-mkrescue`, so the same image contains a BIOS
El Torito image and a UEFI El Torito image. Secure Boot is not enabled; disable
it in firmware or enroll your own keys.

## Frugal install boot chain

```
GRUB (live partition or ESP)
  linux /aether/vmlinuz boot=live components live-media-path=/aether \
        persistence persistence-label=AETHER-DATA quiet preempt=full
  initrd /aether/initrd.img
        │
        ▼
  SquashFS lower layer + writable overlay directories on AETHER-DATA
```

`AETHER-DATA` contains `persistence.conf` with `/ union`, so the whole root
overlay persists. Kernel, initramfs, and SquashFS stay under ~500 MB. User
installs, caches, and changes live in the overlay and consume data-partition
space.

A **full install** instead copies the live rootfs to ext4 and boots with
`root=UUID=...`. It is simpler and more robust, but its base is larger than
512 MB.

## Memory model

- **No disk swap.** ZRAM provides compressed swap in RAM (half of RAM, capped
  at 4 GB, zstd). This is essential on eMMC and within a 2 GB VM.
- **Volatile journal.** `Storage=volatile`, 32 MB cap. No eMMC wear from logs.
- **earlyoom** kills browsers/Wine/Android before the compositor or systemd.
- **Systemd trim.** Daily apt timers, man-db, e2scrub, logrotate, dpkg backups,
  motd-news, and systemd-oomd are masked.
- **No display manager.** getty autologin starts labwc from `.bash_profile`;
  that saves the greeter's memory. The full installer removes autologin and
  leaves a console login, after which `.bash_profile` starts labwc.

## Storage model

| Layer | Approx. size | Writable? |
|---|---:|---|
| GRUB + kernel + initrd | 40–70 MB | no (ISO) |
| SquashFS core | 350–450 MB | no |
| Live overlay (RAM) | 0 until writes | yes, volatile |
| Frugal persistence | grows with use | yes, `AETHER-DATA` |
| Full install root | 1.1–1.5 GB | yes, ext4 |
| Wine pack | ~450 MB | overlay/full root |
| Waydroid pack | ~1.2 GB incl. images | overlay/full root |

Build-time disk is larger: `debootstrap` + installed packages + apt metadata +
SquashFS output + ISO. Budget ~5–7 GB transiently. `AETHER_LOW_DISK=1` purges
apt archives and lists after each stage. Reclaim with `sudo scripts/clean.sh`.

## Desktop processes

`labwc` is the compositor/window manager. It has no built-in panel, so Waybar
draws the top bar. `swaybg` paints a pre-blurred SVG wallpaper. `foot` is the
terminal, `fuzzel` the launcher, `mako` notifications, `swaylock` the locker.
`xdg-desktop-portal-wlr` provides screencast/screenshot portals. PipeWire +
wireplumber handle audio with a small footprint.

"Liquid Glass" is implemented as:

- dark, high-contrast palette with cyan/violet accents;
- translucent Waybar/foot/GTK surfaces and 1 px light borders;
- large, soft light fields baked into the wallpaper;
- rounded corners and drop shadows from labwc;
- no live backdrop-blur shader, because upstream labwc 0.8.3 does not provide
  one and a patched compositor would be a separate maintenance burden.

## Compatibility layer

```
MIME database (shared-mime-info)
  application/x-ms-dos-executable → aether-exe.desktop  → aether-exe  → Wine
  application/x-msi                → aether-exe.desktop  → aether-exe  → msiexec
  application/x-apple-diskimage    → aether-dmg.desktop  → aether-dmg  → dmg2img + 7z
  application/vnd.android...       → aether-apk.desktop  → aether-apk  → Waydroid
  application/x-ios-app            → aether-ipa.desktop  → aether-ipa  → unzip + plistlib
  application/vnd.debian...        → aether-deb.desktop  → aether-deb  → apt
```

Every handler except `.deb` asks for confirmation before executing. Setting
`AETHER_TRUST=1` bypasses the prompt; do not set it globally. Wine uses a
per-application prefix under `~/.local/share/aether/wine/`, so one broken
installer does not poison every app. Waydroid and Wine are installed only by
`aether-pack`.

## Build pipeline

```
00 host-check     tools, Debian host, disk, mirror, GRUB modules
10 fetch-base     debootstrap trixie + apt trim policy + chroot mounts
20 configure      users, systemd policy, network, initramfs, overlay
30 desktop        labwc/Waybar/foot/fuzzel/mako/GTK/Chromium/Astra
40 compat         MIME XML, desktop entries, Wine/Waydroid glue
50 kernel         stock kernel (default) or custom fragment build
60 squashfs       strip docs/locales, ZSTD squashfs, manifest
70 iso            GRUB hybrid ISO, size enforcement, checksums
```

Stages are numbered and mostly idempotent. Re-running `build.sh` reuses an
existing `build/rootfs` if `.aether-base` exists; use `clean.sh --build` for a
clean build.
