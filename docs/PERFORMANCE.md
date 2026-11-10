# Performance and the 120 FPS claim

AetherOS is tuned for **responsiveness on weak x86 hardware**, not for a
guaranteed frame rate. The 120 FPS target is a tuning direction. Three ceilings
are outside the operating system's control:

1. **Panel refresh rate.** A 60 Hz eDP panel displays at most 60 distinct frames
   per second. No kernel setting changes that.
2. **GPU.** A Celeron/Atom iGPU cannot render modern 3D games at 120 FPS. Light
   2D titles and the desktop can hit the panel limit.
3. **VirtualBox.** 3D acceleration is a translation layer. It is fine for
   compositing; it is not a passed-through GPU and will not deliver high-FPS 3D.

The honest goal is: the desktop feels instant, input latency is low, the machine
does not swap itself to death, and lightweight games run at the panel's limit.

## What the image actually changes

### Kernel

- ISO command line adds `preempt=full`. Debian's stock kernel is built with
  `CONFIG_PREEMPT_DYNAMIC`, so this activates full preemption without a compile.
- `--custom-kernel` merges `config/kernel/aetheros.fragment`: 1000 Hz,
  `PREEMPT`, PSI, ZRAM/zstd, BFQ, Binder for Waydroid, and VirtIO/VirtualBox
  storage/graphics modules.
- The custom kernel does **not** apply the out-of-tree PREEMPT_RT patch. RT is a
  different kernel and is not required for desktop responsiveness.

### Memory

```ini
# /etc/systemd/zram-generator.conf
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
```

- No disk swap. ZRAM compresses cold pages instead of writing to eMMC.
- `vm.swappiness=180`, `vm.watermark_boost_factor=0`,
  `vm.min_free_kbytes` is scaled down for small machines.
- `earlyoom` kills the largest memory hog before the compositor or systemd is
  OOM-killed. Browser tabs are the usual victim; that is intentional.

Check it:

```sh
zramctl
free -h
systemctl status earlyoom
journalctl -u earlyoom -n 20
```

### I/O

- BFQ is selected for `mmcblk*`/`sd*` rotational or eMMC devices; `mq-deadline`
  for NVMe. The udev rule is `/etc/udev/rules.d/60-aether-io.rules`.
- `vm.dirty_background_ratio=5`, `vm.dirty_ratio=10`: less bursty writeback on
  slow eMMC.
- journald is volatile with a 32 MB cap. No log writes wear the disk or wake it.
- APT daily timers, man-db, e2scrub, logrotate, motd-news, and systemd-oomd are
  masked. Update manually with `sudo apt update && sudo apt full-upgrade`.

### Graphics

- Mesa is present with the common DRI drivers; Chromium uses the Wayland Ozone
  path when available.
- `WLR_RENDERER_ALLOW_SOFTWARE=1` is a debugging fallback, not a performance
  mode. If you need it, the VM/GPU setup is wrong.
- Tearing is permitted only for fullscreen windows in labwc's `rc.xml`. Desktop
  windows stay tear-free.

### Browser

`aether-browser` passes low-end flags: renderer process limit, process-per-site,
low-end device mode, and a basic password store. These reduce memory, not magic.
A single heavy web app can still exceed the entire idle budget.

### Game Mode

`aether-gamemode` toggles:

- `performance` CPU governor (if the driver exposes it);
- a higher GPU frequency policy where available;
- a do-not-disturb notification state;
- a Waybar `GAME` indicator.

```sh
aether-gamemode status
aether-gamemode toggle
```

It cannot raise a 60 Hz panel, add a GPU, or bypass VirtualBox's renderer.

## Measuring

```sh
# Is ZRAM active?
zramctl

# CPU frequency/governor
cpupower frequency-info        # if linux-cpupower is installed
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# GPU renderer (XWayland or native Wayland)
glxinfo -B | head -20
eglinfo 2>/dev/null | head -20

# A rough X11/XWayland frame test; not a game benchmark
vblank_mode=0 glxgears

# Per-process memory, sorted
ps -eo pid,comm,rss --sort=-rss | head -15

# Did earlyoom kill something?
journalctl -u earlyoom --no-pager | tail -20
```

`glxgears` is a synchronization test, not a GPU benchmark. Use a real game or
`vkmark`/`gfxbench` if you need numbers, and record the resolution, panel Hz, and
whether the VM has 3D acceleration.

## Tuning recipes

### Make the desktop leaner

```sh
# Disable the panel and notifications for a pure game session
pkill waybar
pkill mako

# Stop the browser's background mode
pkill chromium
```

### Inspect and clear the browser profile

```sh
du -sh ~/.config/chromium ~/.cache/chromium
rm -rf ~/.cache/chromium
```

### Free build/install space

```sh
sudo scripts/clean.sh --build     # on the build host
sudo apt clean
sudo journalctl --vacuum-size=8M
```

### If animations feel slow in VirtualBox

- VMSVGA + 128 MB VRAM + 3D acceleration is the intended setting.
- VBoxSVGA with 3D **off** is often more stable; it is slower for compositing.
- Increase VM RAM to 3 GB if the host allows it; Chromium plus Waydroid needs it.
- Do not run a browser inside the VM while expecting the 300 MB idle figure.

## What would be required for a real 120 FPS target

- A panel with a 120 Hz mode and a compositor configured to use it.
- A GPU with enough fill rate for the title at the chosen resolution.
- Direct scanout/fullscreen unredirect and, ideally, adaptive sync.
- A kernel/GPU driver with working power management; a Celeron iGPU may thermally
  throttle before it reaches 120 FPS even in 2D.
- For Windows games: DXVK/VKD3D and a Vulkan driver; for Android: a binder kernel
  and x86_64 APKs.

AetherOS provides the software half (scheduler, I/O, memory, compositor flags).
It does not pretend to provide the hardware half.
