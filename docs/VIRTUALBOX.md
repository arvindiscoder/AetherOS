# VirtualBox guide (16 GB host budget)

AetherOS is designed to run in a 12 GB virtual disk with 2 GB RAM. The ISO is
under 500 MB and the VDI is dynamically allocated, so it does not immediately
consume 12 GB on the host. Snapshots and browser caches do.

## 1. Create the VM

Replace `/path/to/aetheros-0.1-amd64.iso` with the real path.

```sh
VBOX=/usr/bin/VBoxManage
VM=AetherOS

$VBOX createvm --name "$VM" --ostype Debian_64 --register

$VBOX modifyvm "$VM" \
  --memory 2048 --cpus 2 --vram 128 \
  --graphicscontroller vmsvga --accelerate3d on \
  --firmware efi --rtcuseutc on \
  --audio-driver alsa --audio-controller hda --audio-in on --audio-out on \
  --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2222,,22" \
  --boot1 dvd --boot2 disk --boot3 none --boot4 none \
  --clipboard-mode bidirectional --draganddrop bidirectional

$VBOX createmedium disk \
  --filename "$HOME/VirtualBox VMs/$VM/AetherOS.vdi" \
  --size 12288 --format VDI --variant Standard

$VBOX storagectl "$VM" --name SATA --add sata --controller IntelAhci --portcount 2
$VBOX storageattach "$VM" --storagectl SATA --port 0 --device 0 \
  --type hdd --medium "$HOME/VirtualBox VMs/$VM/AetherOS.vdi"
$VBOX storageattach "$VM" --storagectl SATA --port 1 --device 0 \
  --type dvddrive --medium /path/to/aetheros-0.1-amd64.iso

$VBOX startvm "$VM"
```

`--size 12288` is 12 GiB. Do **not** use `--variant Fixed`: a fixed VDI reserves
all 12 GB immediately and leaves no room for the ISO and host snapshots on a
16 GB drive.

### GUI equivalents

| Setting | Value |
|---|---|
| System → Base Memory | 2048 MB (3072 MB only if you will run Waydroid) |
| System → Processors | 2 |
| System → Enable EFI | checked |
| Display → Controller | VMSVGA |
| Display → Video Memory | 128 MB |
| Display → Enable 3D Acceleration | checked |
| Storage | SATA, disk on port 0, ISO DVD on port 1 |
| Network → Adapter 1 | NAT |
| Boot Order | Optical, Hard Disk |

VirtualBox's 3D acceleration is a translation layer, not a real GPU passthrough.
It is enough for labwc/Waybar compositing and light games; it is not a 120 FPS
3D solution, and some Mesa/EGL paths fail under VMSVGA.

## 2. First boot

The live session autologins as `aether` with no password and passwordless sudo.
Useful checks:

```sh
cat /etc/aether-build
free -h
aether-pack list
aether-browser
```

If the screen stays black, reboot and pick **Live (safe graphics)** in GRUB. If
Chromium is empty or crashes, try:

```sh
WLR_RENDERER_ALLOW_SOFTWARE=1 labwc
```

or switch the VM to **VBoxSVGA** with 3D acceleration disabled to isolate the
VirtualBox graphics path.

## 3. Install to the virtual disk

Inside the live session:

```sh
sudo aether-install
```

- Select the **12 GB VDI**, not the ISO/DVD device.
- Choose **full** for a conventional writable install (~1.3 GB used).
- Choose **frugal** only if you specifically need the ≤512 MB base; it uses a
  2 GB `AETHER-LIVE` partition and an `AETHER-DATA` persistence partition.
- Type `ERASE` when prompted. The installer refuses disks smaller than 8 GB and
  refuses the disk that holds the running live medium.

When it finishes, power off, detach the ISO, and boot the VDI:

```sh
$VBOX controlvm "$VM" poweroff
$VBOX storageattach "$VM" --storagectl SATA --port 1 --device 0 --type dvddrive --medium none
$VBOX modifyvm "$VM" --boot1 disk --boot2 dvd
$VBOX startvm "$VM"
```

With EFI enabled, the installer writes a removable-path fallback
(`EFI/BOOT/BOOTX64.EFI`) and attempts a BIOS GRUB install as well. If the
firmware boot menu does not show AetherOS, open the VM's boot menu and select
the virtual disk manually.

## 4. Storage math for 16 GB

| Item | Size |
|---|---:|
| `aetheros-0.1-amd64.iso` | ~450–500 MB |
| Dynamic VDI (grows with use) | 1.5 GB after full install; up to 12 GB |
| Build directory (if building in the same VM) | 4–7 GB transient |
| Wine pack | ~450 MB |
| Waydroid pack + images | ~1.2 GB |
| Browser/profile caches | unbounded; clear them |

A full install plus Wine plus Waydroid can approach 4 GB, leaving ~8 GB of the
VDI unused. That is comfortable. Do not enable VirtualBox snapshots casually:
each snapshot stores changed blocks and can consume the host's remaining space.
Delete the ISO and `build/` from the host after a successful install.

## 5. Waydroid in VirtualBox

Waydroid is a container, not a nested VM, so VirtualBox's nested-virtualization
setting is not the blocker. The blocker is the kernel: stock Debian does not ship
`binder_linux`. The default AetherOS ISO therefore cannot run Waydroid. To test
Android apps, build with `--custom-kernel` (slow) or install a binder-enabled
kernel/DKMS module, then:

```sh
sudo aether-pack install waydroid
sudo waydroid init -s VANILLA
sudo systemctl enable --now waydroid-container
```

Use 3072 MB RAM for the VM if you do this; Android plus Chromium in 2 GB is
tight. ARM-only APKs will not run without proprietary translation libraries.

## 6. Common problems

| Symptom | Fix |
|---|---|
| `FATAL: No bootable medium found` | Attach the ISO to the DVD port, set boot order to optical first |
| UEFI shell instead of GRUB | Enable EFI; if it still fails, test the ISO in QEMU to distinguish image vs VM firmware |
| Black screen after GRUB | Boot **safe graphics** (`nomodeset`); disable 3D acceleration |
| `labwc: EGL error` | Set `WLR_RENDERER_ALLOW_SOFTWARE=1` for a test; use VMSVGA or VBoxSVGA |
| No audio | Set controller to Intel HDA and host driver to ALSA/PulseAudio; unmute in `pavucontrol` if installed |
| Installer cannot see the VDI | The VDI is attached as a disk; run `lsblk` and select that device, not `/dev/sr0` |
| ISO larger than 500 MB | Rebuild with `--no-browser`; see `docs/BUILD.md` |

For a clean reset, delete the VM and its VDI from VirtualBox; the ISO can be
regenerated. Keep the checksum and manifest for any bug report.
