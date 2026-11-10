# AetherOS Handoff

## Project

- Path: `/home/arvind/Downloads/AtherOS/AetherOS`
- Status: buildable on a Debian/Ubuntu host. The ISO has been built and booted in VirtualBox.
- Current ISO: approximately 678 MB with Chromium included.
- Use `--no-browser` for a smaller image, or `--allow-large` to accept the current size.

## What is working

- Debian trixie minbase + labwc live boot now works.
- SquashFS mount-point directories (`proc`, `sys`, `dev`, `run`, `tmp`) are preserved, fixing the earlier `mount: /root/dev: mount point does not exist` failure.
- Live login is automatic as user `aether`.
- The desktop now uses a macOS-inspired layout: a slim translucent menu bar, a floating centered app dock with launchers and running-app icons, and an original blue/purple/pink glass-wave wallpaper.
- The menu bar includes Wi-Fi, Bluetooth, brightness, audio, battery, clock, and a quick-settings popup. Server-decorated windows use traffic-light colored native controls.
- See `docs/DESKTOP.md` for the visual component map and the limits of live blur, dynamic tinting, and refraction under labwc 0.8.3.
- `WLR_NO_HARDWARE_CURSORS=1` was added to reduce VirtualBox cursor lag.
- The normal session no longer enables `WLR_RENDERER_ALLOW_SOFTWARE=1`; keep it as an opt-in recovery test because software rendering can add latency.

## Open issue: mouse cursor delay / apparent self-movement

Symptom:
- The pointer responds, but with a long delay.
- It can appear to be moving by itself.

This is not caused by an AetherOS background process. AetherOS does not generate pointer movement. Likely causes are VirtualBox input integration, host mouse/trackpad input, or the VM graphics/input path.

Troubleshooting:
1. Toggle VirtualBox mouse integration with Host key + `I`.
2. Switch the VM pointing device to **PS/2 Mouse** and disable/remove the **USB Tablet**.
3. Disable **3D Acceleration**, or switch from **VMSVGA** to **VBoxSVGA**.
4. Check whether the cursor also moves in firmware/GRUB before AetherOS boots.
5. Test the host mouse/trackpad outside the VM.
6. Inside AetherOS, run:
   ```sh
   cat /proc/bus/input/devices
   ```
   and save the output for diagnosis.
7. Try:
   ```sh
   WLR_RENDERER_ALLOW_SOFTWARE=1 labwc
   ```

## Build and test commands

```bash
cd /home/arvind/Downloads/AtherOS/AetherOS
sudo ./scripts/clean.sh --build
sudo ./build.sh --allow-large
```

For a smaller image:

```bash
sudo ./build.sh --no-browser --allow-large
```

## Install

Inside the live session:

```sh
sudo aether-install
```

- Select the 12 GB VDI, not the ISO/DVD.
- Choose `full` for a normal writable install.
- Type `ERASE` when prompted.

## Known limitations

- True live backdrop blur is not available in labwc 0.8.3. The Liquid Glass look is an approximation using translucent surfaces, shadows, borders, and a pre-blurred wallpaper.
- Windows support is Wine-based and not perfect for anti-cheat or kernel drivers.
- macOS `.dmg` support can use optional Darling for compatible x86_64 apps.
  Roblox has a dedicated optional Quadra launcher that uses the Mac Player;
  Roblox does not officially support Linux and the third-party route is not
  guaranteed. Generic Mac GUI support remains experimental.
- Android `.apk` support requires Waydroid and works best with x86_64 APKs.
- iOS `.ipa` support is inspection only.
- Waydroid requires a binder-enabled kernel; build with `--custom-kernel` for
  the AetherOS compatibility image.

## Next steps

1. Rebuild with the latest mouse and Liquid Glass changes.
2. Confirm whether `WLR_NO_HARDWARE_CURSORS=1` removes the cursor delay.
3. If the cursor still drifts, collect `/proc/bus/input/devices` and VM input settings.
4. Test full install and installed-disk boot.
5. Test browser, Astra assistant, terminal, launcher, audio, and Wi-Fi.
6. If optimizing size, inspect large packages with:
   ```sh
   dpkg-query --admindir=build/rootfs/var/lib/dpkg -W -f='${Installed-Size}\t${Package}\n' | sort -rn | head -30
   ```
