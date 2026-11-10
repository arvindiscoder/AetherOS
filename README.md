# AetherOS

**AetherOS 0.1 "Nimbus"** — a hyper-lightweight Debian-based live/installable
OS blueprint, built for a 16 GB budget.

AetherOS is a Wayland desktop built on Debian 13 ("trixie"), `labwc`, and a
purpose-built "Liquid Glass" shell. The core image is designed to fit in a
512 MB ISO and to idle near 300 MB of RAM. Heavy compatibility runtimes are
delivered as optional, separately built *packs* so they never inflate the core
image.

> **Status:** this is a complete, auditable build system and configuration set,
> not a prebuilt binary ISO. You must run `sudo ./build.sh` on a Debian/Ubuntu
> host with ~10 GB free disk and network access. The build is designed to fit a
> 16 GB VirtualBox guest when the VM disk is 12 GB and the ISO is stored on the
> host.
>
> **Build status:** shell syntax, JSON, XML, executable, and packaging checks
> pass via `make lint`/`tests/lint.sh`. The ISO has **not** been built or booted
> in the authoring environment (a Flatpak runtime without `debootstrap`,
> `mksquashfs`, `xorriso`, or GRUB). Treat the first Debian-host build and the
> VirtualBox boot as bring-up tests. See **Known gaps** below.

---

## The honest parts first

The blueprint asks for capabilities that do not exist as described. Pretending
otherwise would waste your 16 GB and your time. Here is exactly what this
project does:

| Requested | AetherOS delivers | Reality |
|---|---|---|
| Windows `.exe` / `.msi` | Wine pack, MIME integration, isolated prefixes, optional sandbox | **Works** for many 64-bit Win32 apps; games vary. 32-bit needs the `wine32` pack (adds ~700 MB). |
| macOS `.dmg` | `aether-dmg`: inspect/extract and experimental generic launch; optional Quadra pack for Roblox's Mac client | **Experimental.** Darling GUI compatibility is limited. Roblox's unofficial Quadra launcher is app-specific; Roblox does not support Linux. |
| Android `.apk` | Waydroid pack, floating windows, MIME integration | **Works** on x86_64 APKs when booted with the compatibility kernel and binder. ARM APKs need proprietary translation, which is not bundled. |
| iOS `.ipa` | `aether-ipa`: unpack, inspect `Info.plist`, report architecture, extract assets | **Cannot execute.** There is no open-source iOS runtime; Corellium is a commercial ARM virtualization product and is not redistributable. No legal path to run arbitrary IPAs here. |
| 120 FPS gaming | `aether-gamemode`, 1000 Hz/preempt kernel config, BFQ on eMMC, ZRAM, Mesa/Wine tuning, tearing support | **Tuning, not a guarantee.** A Celeron iGPU and a 60 Hz panel cannot reach 120 FPS in modern games. Lightweight 2D/emulated titles can hit the panel limit. |
| ≤300 MB idle | `labwc` + `waybar` + `foot` + minimal systemd, no browser at idle | **Plausible (~250–290 MB)** with the browser closed. A Chromium window adds 150–300 MB. |
| ≤512 MB installed | Core ISO target ≤450 MB; frugal install uses SquashFS + overlay | A normal writable install with Chromium is ~1.1–1.4 GB. Use **frugal mode** to keep the base under 512 MB, or accept the larger full install. |
| ChatGPT Astra | Configurable assistant surface, Chromium extension (omnibox + side panel + context menu), `Super+Space` | **"ChatGPT Astra" is not a public product/API.** The integration points to a configurable URL (default `chatgpt.com`) and supports an OpenAI API key for the side panel. |

This is how a real distro handles incompatible ecosystems: a small, reliable
core plus signed, optional runtime packs. The core stays fast; the user chooses
the weight.

---

## 16 GB survival plan

You said the VM gets **16 GB total**. Use this layout:

| Allocation | Size | Why |
|---|---:|---|
| VM disk (VDI, dynamically allocated) | **12 GB** | 4 GB root + 7 GB data + 512 MB ESP; leaves headroom |
| ISO storage on host | **≤ 500 MB** | Core ISO only; keep packs on the host, not in the VM |
| VM RAM | **2048 MB** (3072 MB for Waydroid) | 2 GB is enough for labwc + Chromium; 3 GB for Android |
| Host build space | **~6–8 GB** | `debootstrap` rootfs, apt cache, squashfs, ISO |
| Swap | none | ZRAM only; no disk swap on eMMC |

Build with `AETHER_LOW_DISK=1` (the default) to remove apt caches, docs, and
locales after every stage. Do **not** build Wine or Waydroid inside the VM; build
them as packs on the host only if you have extra space, or install them online
inside the VM (`sudo aether-pack install wine`).

### If you only have 16 GB on the host too

1. Build the core ISO (needs ~5 GB transiently).
2. Delete `build/` immediately: `sudo ./scripts/clean.sh --build`.
3. Keep `out/aetheros-*.iso` and copy it to the VM. The compatibility edition is larger than the minimal core image.
4. Do not build Wine/Waydroid packs on that host; use the online pack installer
   from inside the running VM.

---

## Quick start (Debian/Ubuntu host)

```bash
sudo apt update
sudo apt install -y debootstrap squashfs-tools xorriso grub-pc-bin \
  grub-efi-amd64-bin mtools dosfstools gdisk rsync zstd \
  syslinux-utils isolinux shellcheck

git clone <this-repo> AetherOS && cd AetherOS
sudo ./build.sh
# result: out/aetheros-0.1-amd64.iso
```

The build must run as root (debootstrap/chroot). It refuses to run on a
non-Debian host and checks free space before starting.

```bash
sudo ./build.sh --check          # host + disk check only
sudo ./build.sh --custom-kernel --allow-large  # binder support for Waydroid; larger image
sudo ./build.sh --keep-build     # debug: keep build/rootfs
sudo ./build.sh --low-disk       # default; purge caches aggressively
make lint                        # static checks; no root required
```

---

## What is in the box

```
build.sh                     master orchestrator (00 → 70)
Makefile                     iso, check, lint, clean, VirtualBox helpers
scripts/00-host-check.sh     dependencies, disk, Debian host, 16 GB guard
scripts/10-fetch-base.sh     debootstrap trixie minbase
scripts/20-configure.sh      users, locale, systemd trim, autologin, installer
scripts/30-desktop.sh        labwc, Waybar, foot, fuzzel, mako, theme, browser
scripts/40-compat.sh         MIME types, Wine/Waydroid manifests, helpers
scripts/50-kernel.sh         optional custom kernel (fragment in config/kernel)
scripts/60-squashfs.sh       strip, ZSTD SquashFS, size budget enforcement
scripts/70-iso.sh            GRUB BIOS+UEFI hybrid ISO, checksums
config/                      every desktop/system config, commented
overlay/                     files copied into the rootfs
installer/aether-install     TUI installer: full or frugal mode
docs/                        build, VirtualBox, Chromebook, compatibility
tests/lint.sh                bash -n, XML/JSON validation, executable checks
```

### Known gaps

- **Waydroid on the stock kernel:** Debian does not ship `binder_linux`. The
  `.apk` path works only after `./build.sh --custom-kernel` or a binder-enabled
  kernel/DKMS module. The core ISO alone cannot run Android apps.
- **512 MB is tight with Chromium:** stage 70 hard-fails above 512 MiB. If a
  Debian package update pushes it over, rebuild with `--no-browser` or use
  `--allow-large` explicitly. The 512 MB claim is for the core/frugal base, not
  a full install.
- **Frugal mode keeps the live autologin:** it cannot modify the read-only
  SquashFS at install time. Set a password after first boot or use full mode on
  a shared machine.
- **Installer boot layout is untested on real firmware:** UEFI removable-path
  and BIOS GRUB are both attempted, but test in VirtualBox and on the target
  Chromebook before relying on it. Keep a recovery USB.
- **No live backdrop blur:** labwc 0.8.3 has no upstream blur shader. A
  pre-blurred wallpaper and translucent surfaces approximate the look without a
  patched compositor.

## Documentation

- [`docs/FEASIBILITY.md`](docs/FEASIBILITY.md) — what is possible, what is not, and why
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — boot chain, memory/storage budgets, pack system
- [`docs/BUILD.md`](docs/BUILD.md) — full build walkthrough and troubleshooting
- [`docs/VIRTUALBOX.md`](docs/VIRTUALBOX.md) — exact 16 GB VM settings + `VBoxManage`
- [`docs/CHROMEBOOK.md`](docs/CHROMEBOOK.md) — firmware, USB, partitioning, install
- [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) — 120 FPS tuning, ZRAM, schedulers
- [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) — Wine, DMG, APK, IPA limits

## Default credentials

Live session: user `aether`, **no password**, passwordless `sudo` (live only).
Full install: the installer forces you to set a password and removes the live
sudoers rule. Frugal install: the read-only base keeps the live autologin; run
`passwd` after first boot and remove the autologin drop-in if the machine is
shared.

## License

Build scripts and original configs: MIT. Debian packages retain their own
licenses. Wine, Waydroid, Chromium, and firmware are not bundled into the core
image except where Debian ships them; see `docs/COMPATIBILITY.md`.
