# Feasibility: what AetherOS can and cannot do

This document exists so nobody mistakes a demo for a capability. The blueprint
asks for several things that are not technically possible on a 16 GB, x86,
open-source system. AetherOS implements the honest subset and isolates the
heavy, fragile parts in optional packs.

## Capability matrix

| Request | Status | What actually ships | Hard limits |
|---|---|---|---|
| Debian/Ubuntu `.deb` | **Native** | `apt`, `aether-deb`, full Debian userland | none beyond normal Debian |
| Windows `.exe` / `.msi` | **Works via Wine pack** | Wine 64-bit, isolated prefixes, MIME handler, registry tuning | 32-bit needs `wine32` pack (~700 MB); anti-cheat and kernel drivers fail; performance varies |
| macOS `.dmg` | **Inspect + experimental launch** | Generic Darling pack; Quadra launcher for Roblox Mac Player | Generic GUI support is limited; Roblox is unofficial on Linux and uses a third-party shim; x86_64 only |
| Android `.apk` | **Works via Waydroid pack** | Waydroid + Vanilla image, floating windows, APK handler, binder-enabled compatibility kernel | x86_64 APKs only; ARM translation (`libndk`/`libhoudini`) is proprietary and not bundled |
| iOS `.ipa` | **Inspect only** | Unpack, parse `Info.plist`, architecture/size report | **No execution.** There is no open-source iOS runtime. Corellium is a commercial remote service |
| 120 FPS gaming | **Tuning only** | 1000 Hz/preempt kernel fragment, BFQ, ZRAM, earlyoom, tearing, Mesa/Wine flags | A Celeron iGPU and a 60 Hz panel cannot display 120 FPS. Lightweight/2D titles can hit the panel limit |
| ≤300 MB idle RAM | **Plausible with browser closed** | labwc, Waybar, foot, mako, PipeWire, minimal systemd | Chromium adds 150–300 MB. A heavy site can exceed the budget by itself |
| ≤512 MB installed | **Frugal mode** | SquashFS + persistent overlay; core live files ~400–500 MB | A normal writable full install is ~1.1–1.5 GB. Overlay growth is user data |
| "Liquid Glass" | **Approximation** | Pre-blurred wallpaper, translucent Waybar/foot/GTK surfaces, 1 px light borders, dark palette | labwc 0.8.3 has no upstream backdrop-blur shader. True live blur needs a patched compositor; shipped UI avoids claiming it |
| ChatGPT Astra | **Configurable bridge** | `Super+Space` app window, Chromium omnibox keyword `astra`, context menu, local side panel using an OpenAI API key | "Astra" is not a public OpenAI product/API. No secret endpoint is bundled |
| UEFI + BIOS boot | **Yes** | GRUB2 hybrid ISO via `grub-mkrescue` | Secure Boot must be disabled or keys enrolled manually; Chromebooks need UEFI firmware |
| 16 GB VirtualBox budget | **Yes, if disciplined** | 12 GB dynamic VDI, ≤500 MB ISO, no packs inside the VM by default | Snapshots, Wine, Waydroid images, and browser caches consume the remaining space quickly |

## Why the runtime packs exist

A single image containing Wine, Waydroid, Chromium, Mesa, firmware, and a
custom kernel cannot fit in 512 MB. More importantly, every runtime increases
the attack surface and the boot-time failure modes. The core image is therefore:

- Debian `trixie` minbase
- `labwc` + Waybar + foot + fuzzel + mako
- Chromium (the largest single package)
- Mesa, PipeWire, iwd/systemd-networkd
- the small compatibility glue (`dmg2img`, 7-Zip, `python3`, MIME handlers)

Wine and Waydroid are installed *after* boot with `aether-pack`, either online
or from local `.deb` files. They write to the persistent overlay, not to the
read-only SquashFS.

## The 512 MB claim, precisely

The core ISO target is **≤512 MB**. The base SquashFS is budgeted at ~400 MB,
leaving room for the kernel, initramfs, and GRUB. The live filesystem itself is
read-only; the writable overlay normally lives in RAM.

A **full install** copies the live rootfs to ext4 and is larger than 512 MB once
Chromium and its dependencies are included (~1.1–1.5 GB). Only the **frugal**
install keeps the base under 512 MB: it stores `vmlinuz`, `initrd.img`, and
`filesystem.squashfs` on a small ext4 partition and puts the persistent overlay
on `AETHER-DATA`.

This is the same trade-off every live distro makes. Pretending a full Chromium
desktop plus Wine plus Android fits in 512 MB would be false.

## The 300 MB idle claim, precisely

Measured target **with no browser window**:

| Component | Typical RSS |
|---|---:|
| kernel + firmware | 60–90 MB |
| systemd, journald (volatile), dbus, networkd, iwd | 25–45 MB |
| labwc + XWayland idle | 20–35 MB |
| Waybar | 30–50 MB |
| foot (one window) | 12–20 MB |
| mako, PipeWire, wireplumber | 20–35 MB |
| earlyoom, udev, misc | 5–10 MB |
| **Total** | **~200–290 MB** |

Chromium is not in that number. A single blank Chromium window is commonly
150–250 MB; a few tabs can push total system use past 512 MB. ZRAM and
earlyoom keep the machine usable rather than promising a number Chromium
cannot meet.

## 120 FPS, precisely

There are three independent ceilings:

1. **Display**: a 60 Hz eDP panel can only show 60 distinct frames per second.
2. **GPU**: an Intel UHD/Celeron iGPU cannot render modern 3D titles at 120 FPS
   at native resolution, regardless of scheduler settings.
3. **VirtualBox**: 3D acceleration is a translation layer, not a passthrough
   GPU. It is useful for compositing and light games, not for high-FPS 3D.

What AetherOS actually does: `preempt=full` on the kernel command line, a 1000
Hz custom-kernel option, BFQ on eMMC, ZRAM swap, a low-dirty-writeback policy,
tearing allowed only for fullscreen, Mesa threaded submission, and Game Mode
which switches to the performance governor. It does not promise 120 FPS.

## What is deliberately absent

- A patched wlroots/labwc build with live blur. It would add build complexity
  and fragment the compositor for a cosmetic effect that a pre-blurred
  wallpaper approximates on low-end GPUs.
- Wine, Waydroid, Darling, and iOS runtimes in the core ISO.
- Proprietary ARM translation libraries for Android.
- Any claim that `.ipa` execution is available through Corellium; that is a
  separate commercial service and is not integrated here.
- A custom kernel by default. It is opt-in because it needs ~2.5 GB extra disk
  and 20–60 minutes; the stock Debian kernel already supports `preempt=full`.

## Recommended user-facing wording

> AetherOS is a tiny Debian/Wayland live system with a glass-styled desktop and
> optional compatibility packs. Windows apps work through Wine, Android apps
> work through Waydroid on supported kernels, disk images can be inspected, and
> iOS apps cannot run on Linux. The ISO is under 512 MB; a full writable install
> is larger, so use frugal mode when the 512 MB base matters.
