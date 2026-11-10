# Chromebook guide (x86 only)

This guide is for **Intel/AMD x86 Chromebooks** with MrChromebox UEFI firmware.
ARM Chromebooks (MediaTek, Rockchip, Qualcomm) need a separate arm64 build and a
different firmware/boot chain; they are out of scope for this ISO.

Flashing firmware and erasing ChromeOS can leave the machine unbootable if you
skip a step. Read the entire guide, make a ChromeOS recovery USB, and back up the
firmware before starting. You accept the risk.

## 1. Confirm the device is supported

1. Open ChromeOS Settings → About → Additional details, or visit
   `chrome://version`, and record the board name (for example `octopus`,
   `grunt`, `hatch`, `volteer`).
2. Check <https://mrchromebox.tech/#devices> for that board.
3. If the board is not listed as UEFI-capable, stop. Do not force a firmware
   from another board.

ChromeOS's own firmware boots only ChromeOS. AetherOS needs either:

- **UEFI firmware** from MrChromebox (recommended), or
- legacy BIOS/SeaBIOS firmware, if your device supports it.

## 2. Prepare recovery and backup

On a working computer:

```sh
# ChromeOS recovery image: use the official Chromebook Recovery Utility.
# Write a recovery USB, then label it so you do not overwrite it later.
```

Boot the Chromebook into recovery (Esc + Refresh + Power, then Ctrl+D) and make
sure the recovery USB works **before** modifying firmware. On the firmware
screen, use the firmware utility's backup option if offered; save the backup on
another USB. Losing the original firmware can make warranty service difficult.

## 3. Enable developer mode and disable write protect

1. Enter recovery mode, press Ctrl+D, confirm, and wait for developer mode.
2. On the developer-mode warning screen, press Ctrl+D to boot; do not press
   Space (that returns to verified boot).
3. Open a crosh shell: Ctrl+Alt+T, type `shell`.
4. Run the MrChromebox firmware utility:

   ```sh
   cd ~
   curl -LO https://mrchromebox.tech/firmware-util.sh
   sudo bash firmware-util.sh
   ```

5. Choose the UEFI firmware option for your device. The script will explain how
   to disable firmware write protect. On many models this means removing the
   bottom cover and disconnecting the battery, or removing a write-protect
   screw; on others it is a jumper. Follow the on-screen instructions exactly.
6. Re-run the utility after disabling write protect, select **Install/Update
   UEFI Firmware**, and let it finish. Do not power off during the write.

After reboot, the Chromebook should show a UEFI boot menu instead of the ChromeOS
warning screen. If it still boots ChromeOS, write protect was not disabled or
the firmware install did not complete.

## 4. Write the AetherOS USB

Use a USB drive of at least 2 GB. This erases the entire USB drive.

```sh
sha256sum -c aetheros-0.1-amd64.iso.sha256
lsblk                       # identify the USB, e.g. /dev/sdb — NOT your disk
sudo dd if=aetheros-0.1-amd64.iso of=/dev/sdb bs=4M status=progress oflag=sync
sync
```

On Windows/macOS, use **Ventoy** or **Rufus** (GPT + UEFI, dd mode). Ventoy is
convenient because it can hold several ISOs, but a direct `dd` write is the most
predictable for firmware testing. Verify the checksum before writing.

## 5. Boot the USB

1. Insert the USB, power on, and press the firmware boot-menu key (often Esc,
   F7, F10, or F12; MrChromebox displays the correct key).
2. Select the USB under **UEFI** (not legacy, unless you intentionally installed
   BIOS firmware).
3. Choose **AetherOS — Live**. If the panel stays black, choose **safe graphics**.
4. The live session autologins as `aether`. Check that Wi-Fi, keyboard,
   brightness, and trackpad work before installing.

Some Chromebooks need `i915.enable_psr=0` or a panel-specific kernel parameter.
Add it temporarily in GRUB by pressing `e`, editing the `linux` line, and
booting with Ctrl+X. Only make it permanent after confirming it helps.

## 6. Install and partition

The internal eMMC is usually 32–128 GB; the 16 GB VirtualBox budget does not
apply. A 64 GB Chromebook is comfortable:

- **Full install**: ~1.3 GB used, leaves the rest for data. Recommended.
- **Frugal install**: 2 GB `AETHER-LIVE` + data/persistence partition. Useful
  for a very small eMMC or for keeping the base under 512 MB.

Inside the live session:

```sh
lsblk
sudo aether-install
```

Select the internal eMMC (for example `/dev/mmcblk0`), not the USB. The installer
creates a GPT with a 1 MB BIOS boot partition, a 512 MB EFI system partition, and
the root or live/data partitions depending on mode. It refuses the disk holding
the live USB.

For a manual layout (advanced), the minimum is:

```sh
sudo sgdisk --zap-all /dev/mmcblk0
sudo sgdisk -n 1:0:+1M   -t 1:ef02 -c 1:"BIOS boot" /dev/mmcblk0
sudo sgdisk -n 2:0:+512M -t 2:ef00 -c 2:"AETHER-EFI" /dev/mmcblk0
sudo sgdisk -n 3:0:0     -t 3:8300 -c 3:"AETHER-ROOT" /dev/mmcblk0
sudo mkfs.fat -F32 -n AETHER-EFI /dev/mmcblk0p2
sudo mkfs.ext4 -L AETHER-ROOT /dev/mmcblk0p3
```

Then run the installer, which handles the copy and GRUB. Do not hand-write a
GRUB config until the installer path is known to boot.

### Firmware boot entry

If the Chromebook ignores the installed disk, open the firmware boot menu and
select `EFI/BOOT/BOOTX64.EFI` on the internal disk. The installer uses GRUB's
removable fallback path precisely for this case. You can add a permanent entry
with `efibootmgr` from the live session, but many Chromebooks reset NVRAM on
firmware updates; the removable path is more durable.

## 7. First boot and hardware

```sh
iwctl                       # Wi-Fi: station wlan0 scan / connect
nmcli device status         # only if NetworkManager was installed manually
brightnessctl set 60%
```

If Wi-Fi is missing, confirm the firmware package for your card is installed
(`firmware-iwlwifi`, `firmware-atheros`, `firmware-mediatek`, or
`firmware-brcm80211`). Some Chromebooks use a MediaTek or Qualcomm card that
needs a newer kernel/firmware than Debian stable provides.

Trackpad, keyboard backlight, and audio on Chromebooks are board-specific. The
core image includes common HID/I2C and SOF audio modules, but not every
Chromebook's amplifier topology. Report the board name if something is missing;
do not assume a generic fix.

## 8. Recovery and rollback

- To return to ChromeOS, use the ChromeOS recovery USB and the recovery mode
  key combination. This erases the disk again.
- To restore original firmware, use the backup made by the firmware utility.
  If you did not make one, check MrChromebox's documentation for a recovery
  image for your board; not every board has one.
- Keep the AetherOS USB until the installed system has booted at least twice.

## 9. What not to do

- Do not flash an ARM Chromebook with this ISO.
- Do not use a random "UEFI firmware" from a forum; use MrChromebox for supported
  boards.
- Do not run the installer against `/dev/mmcblk0` while the live USB is the only
  disk you can see; re-check `lsblk`.
- Do not expect Secure Boot to work. Disable it or enroll keys; the shipped GRUB
  is unsigned.
- Do not expect `.ipa` execution or ARM Android apps. See `docs/COMPATIBILITY.md`.
