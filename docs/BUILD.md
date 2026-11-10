# Build guide

AetherOS is built on a **Debian or Ubuntu host** with root, `debootstrap`, the
GRUB module trees, and about 8–12 GB of free disk. Building inside a Flatpak
sandbox or an unprivileged container will fail at `mount`/`chroot`; use a full
VM or bare-metal Debian install.

The build has not been executed in this repository's authoring environment
(a Flatpak runtime without `debootstrap`, `mksquashfs`, `xorriso`, or GRUB).
Treat the first run as a bring-up: fix host-package differences, then test the
ISO in VirtualBox before writing it to a Chromebook.

## 1. Host packages

Debian 13 (trixie) or Debian 12 with bookworm-backports:

```sh
sudo apt update
sudo apt install -y \
  debootstrap squashfs-tools xorriso mtools dosfstools gdisk \
  grub-pc-bin grub-efi-amd64-bin grub-common \
  rsync zstd curl gpg ca-certificates \
  syslinux-utils isolinux file
```

Optional validation tools:

```sh
sudo apt install -y shellcheck jq libxml2-utils qemu-system-x86
```

Check the two GRUB trees exist; the ISO cannot be hybrid without both:

```sh
test -d /usr/lib/grub/x86_64-efi && echo UEFI-ok
test -d /usr/lib/grub/i386-pc    && echo BIOS-ok
```

## 2. Build

From the project root:

```sh
sudo ./build.sh --check          # host validation only
sudo ./build.sh                  # core ISO, low-disk mode
ls -lh out/
```

A successful run leaves:

```
out/aetheros-0.1-amd64.iso
out/aetheros-0.1-amd64.iso.sha256
out/aetheros-0.1-amd64.manifest.txt
out/aetheros-0.1-amd64-boot.txt
```

The ISO is refused if it exceeds 512 MiB. `--allow-large` bypasses that check
for experiments, but a >512 MB image does not meet the stated budget.

### Flags

| Flag | Effect |
|---|---|
| `--check` | Run host checks and exit; no rootfs changes |
| `--no-browser` | Omit Chromium; ISO shrinks by roughly 120–180 MB, no default browser |
| `--custom-kernel` | Compile the low-latency fragment (20–60 min, +2.5 GB) |
| `--low-disk` / `--no-low-disk` | Purge apt archives after each stage (default on) |
| `--keep-build` | Keep `build/` for debugging (it is kept anyway until you clean) |
| `--allow-large` | Do not fail when the ISO exceeds 512 MiB |

Environment overrides:

```sh
sudo AETHER_BUILD=/mnt/fast/aether-build ./build.sh
sudo AETHER_MIRROR=http://ftp.debian.org/debian ./build.sh
sudo AETHER_SUITE=bookworm ./build.sh       # best-effort; trixie is primary
```

## 3. Pipeline

| Stage | File | What happens |
|---|---|---|
| 00 | `scripts/00-host-check.sh` | Tools, Debian detection, network, disk space, GRUB trees |
| 10 | `scripts/10-fetch-base.sh` | `debootstrap --variant=minbase trixie`, apt trim policy, chroot mounts |
| 20 | `scripts/20-configure.sh` | Users, sudo/autologin, services, iwd/networkd, sysctl, ZRAM, initramfs |
| 30 | `scripts/30-desktop.sh` | labwc, Waybar, foot, fuzzel, mako, GTK, wallpaper, Chromium, Astra extension |
| 40 | `scripts/40-compat.sh` | MIME XML, desktop entries, Wine registry, Waydroid sample |
| 50 | `scripts/50-kernel.sh` | Validate stock kernel or build `config/kernel/aetheros.fragment` |
| 60 | `scripts/60-squashfs.sh` | Strip docs/locales, copy kernel/initrd, ZSTD SquashFS, manifest |
| 70 | `scripts/70-iso.sh` | `grub-mkrescue` hybrid ISO, checksum, 512 MiB enforcement |

`build.sh` runs 00→70. Each stage can be re-run manually with the exported
environment (use `build.sh` rather than sourcing stages directly):

```sh
sudo ./build.sh                 # safe to re-run; 10 reuses an existing rootfs
sudo ./scripts/clean.sh --build # remove build/ (unmounts chroot first)
sudo ./scripts/clean.sh         # remove build/ and generated out/ files
```

## 4. Expected sizes

| Artifact | Target | Notes |
|---|---:|---|
| Rootfs before stripping | 1.3–1.8 GB | Includes apt metadata and docs |
| SquashFS | 350–450 MB | Chromium dominates; zstd -19 |
| Kernel + initrd | 50–90 MB | Debian kernel; initrd uses `MODULES=most` |
| ISO | ≤512 MiB | Hard-fails in stage 70 |
| Full installed system | 1.1–1.5 GB | Writable ext4, not a 512 MB claim |
| Frugal base | ≤512 MB | SquashFS + kernel + initrd on `AETHER-LIVE` |

If the ISO is close to the limit, the biggest wins are `--no-browser`, dropping
`firmware-*` packages you do not need, and removing `mesa-vulkan-drivers`.

## 5. Test before flashing

```sh
sha256sum -c out/aetheros-0.1-amd64.iso.sha256
qemu-system-x86_64 -m 2048 -smp 2 -enable-kvm \
  -drive file=out/aetheros-0.1-amd64.iso,format=raw,if=virtio \
  -vga std -boot d
```

For VirtualBox, follow `docs/VIRTUALBOX.md`. For a Chromebook, follow
`docs/CHROMEBOOK.md`; do not flash a Chromebook until the ISO boots a VM.

## 6. Troubleshooting

### `debootstrap` cannot fetch Release

Check `/etc/resolv.conf` in the host and `AETHER_MIRROR`. A proxy requires
`http_proxy`/`https_proxy` in the host environment; the chroot gets a copy of
the host resolver, not the host proxy variables.

### `chroot: failed to run command ...`

A previous stage was interrupted with mounts left behind:

```sh
sudo scripts/clean.sh --build
```

or unmount manually:

```sh
for m in dev/pts dev proc sys run; do sudo umount -l build/rootfs/$m 2>/dev/null; done
```

### Missing `systemd-zram-generator` or another package

Stage 20 validates every line in `config/packages.core` with `apt-cache show`
and skips names not present in the suite. A package that is silently skipped may
break a feature; inspect the `warn` lines. Do not add Wine or Waydroid to the
core list.

### `grub-mkrescue` fails

Both GRUB platform packages must be installed on the host. Ensure
`/usr/lib/grub/i386-pc` and `/usr/lib/grub/x86_64-efi` exist. If `-volid` is
rejected by an old xorriso, remove the `-- -volid AETHEROS` suffix.

### ISO is over 512 MiB

Rebuild with `--no-browser`; the browser and its locale/font dependencies are
the largest optional block. `--allow-large` is for experiments only.

### `mksquashfs` killed

`-mem 512M` and `-processors` are capped for 2 GB hosts. If the host is smaller,
close other VMs. Do not run the build inside a 1 GB container.

### Waydroid will not start

The stock Debian kernel does not provide `binder_linux`. The `waydroid` pack is
only functional after `./build.sh --custom-kernel` (which enables the binder
fragment) or after installing a binder-enabled kernel/DKMS module. See
`docs/COMPATIBILITY.md`.

## 7. Reproducibility and release checks

Record the commit, host packages, and `manifest.txt` with any release. The
manifest contains the kernel version, SquashFS hash, and every installed
package/version. The ISO checksum is written next to the image.

A minimal release gate:

1. `bash -n` every `.sh`; `sh -n` every POSIX overlay script.
2. `tests/lint.sh` passes.
3. ISO boots in VirtualBox with EFI **and** legacy BIOS.
4. Live user reaches labwc; terminal, launcher, browser, and `aether-pack list` work.
5. `sudo aether-install` completes a full install to a blank 12 GB disk.
6. The installed disk boots without the ISO attached.
