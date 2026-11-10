# Compatibility guide

AetherOS integrates foreign formats through small, explicit handlers. Nothing
except a Debian package is executed without a confirmation dialog unless
`AETHER_TRUST=1` is set in the environment. That variable is an escape hatch,
not a default; do not export it globally.

| Format | Handler | Runtime | Status |
|---|---|---|---|
| `.deb` | `aether-deb` | `apt`/`dpkg` | Native |
| `.exe`, `.msi` | `aether-exe` | Wine 64-bit (+ optional wine32) | Works with caveats |
| `.dmg` | `aether-dmg` | `dmg2img`, 7-Zip, optional Darling | Inspect/extract older supported images; compatible x86_64 `.app` launch is experimental |
| `.apk` | `aether-apk` | Waydroid + binder kernel | Works on supported kernels; x86_64 APKs only |
| `.ipa` | `aether-ipa` | `unzip`, Python `plistlib` | Inspect only; **cannot execute** |

## Debian packages

```sh
sudo aether-deb ./app.deb
# or
sudo apt install ./app.deb
```

`aether-deb` shows the package metadata in a terminal and asks before calling
`apt`. Dependencies are resolved from the configured Debian repositories. A
package built for a different architecture will fail; this image is `amd64`.

## Windows: Wine

Install the pack:

```sh
sudo aether-pack install wine        # 64-bit Wine, winetricks, cabextract
sudo aether-pack install wine32      # optional 32-bit support (~700 MB)
```

Run a program:

```sh
aether-exe ./setup.exe
# or double-click it in the file manager
```

Wine prefixes are isolated:

```
~/.local/share/aether/wine/<name>/
```

The handler creates a prefix per executable directory (or uses `WINEPREFIX` if
set), applies `config/compat/wine/aether.reg` for DPI/theme defaults, and runs
`wineboot` on first use. `.msi` files are passed to `msiexec /i`.

What works: many 2D apps, older games, portable utilities, installers without
kernel drivers.

What does not: kernel anti-cheat, services that require a Windows kernel driver,
DirectX 12 titles needing a modern Vulkan driver, and anything relying on
Internet Explorer/Edge WebView. Performance in VirtualBox is limited by the
virtual GPU.

## macOS: DMG and Darling

Double-click a `.dmg` in File Manager to open it with **DMG Extractor**. You can
also launch **DMG Extractor** from the AetherOS app menu and select a file.
DMG Extractor is registered for the Apple disk-image type and is available from
File Manager's **Open With** list; double-click uses it as the default handler.
Choose an output folder when prompted. The app tries 7-Zip directly first,
then converts with `dmg2img` and retries extraction. Extracted files remain in
the chosen folder and can be opened from File Manager.

Command-line use:

```sh
aether-dmg ./App.dmg
```

7-Zip cannot read APFS images, which are common in newer Mac installers, and
encrypted images may also fail. Extraction only makes the image's files
available; a `.app` bundle is still a macOS program, not a Linux app.

Running macOS binaries is a different problem. **Darling** is an x86_64
translation layer that reimplements parts of macOS on Linux. It can run many
command-line programs, and current upstream builds include experimental Cocoa
GUI support. GUI compatibility is still limited: many apps, frameworks, and
installers fail, and graphics can be incomplete. This is not a macOS virtual
machine and does not make every `.app` runnable.

Install the optional source-built runtime:

```sh
sudo aether-pack install darling
```

The build is intentionally excluded from the ISO. Darling's upstream build
guide requires x86_64 Linux and at least 4 GiB of RAM; it can use about 5 GiB
for source, up to 16 GiB while building, and up to 1 GiB installed. AetherOS
checks for 4 GiB RAM and 26 GiB free disk before installing dependencies. The
default 3 GiB RAM / 16 GiB VM therefore needs more memory and disk space first.
The installer pins an upstream Darling release and keeps failed build sources
for diagnosis.

After it is installed, extract the DMG and accept the separate prompt to try a
single discovered `.app` with Darling. This launch path is experimental; many
apps will not run. Apps bundled only for Apple Silicon (`arm64`) are not
supported on this amd64 build.

## Roblox: Mac client through Quadra

Roblox is not officially supported on Linux. For a concrete Mac-app example,
AetherOS provides the optional Quadra launcher, which runs the Roblox macOS
Player through Darling and applies Roblox-specific compatibility fixes. It
downloads the current Mac client itself; a Roblox `.dmg` is not required and a
generic DMG opener does not apply Quadra's fixes.

Install Quadra from the AetherOS app menu using **Install Roblox (Mac client)**,
or run:

```sh
sudo aether-pack install roblox
```

Open **Quadra**, choose Darling on its welcome screen, let it install the
runtime and Roblox client, then sign in inside Roblox yourself. The install
needs internet access and several gigabytes of free space. Quadra is an
unofficial third-party project, not endorsed by Roblox; its maintainers state
they cannot guarantee against account suspensions. In VirtualBox, 3D graphics
and gameplay speed depend on the virtual GPU, so installation may succeed even
when a game performs poorly.

## Android: Waydroid

Waydroid runs Android in a container and needs the kernel's binder driver.

```sh
# Check the kernel
lsmod | grep binder
ls -l /dev/binder /dev/binderfs/binder 2>/dev/null

# Install the pack (adds the Waydroid repo if Debian does not provide it)
sudo aether-pack install waydroid
sudo waydroid init -s VANILLA
sudo systemctl enable --now waydroid-container
```

If packaging is missing:

```sh
curl -fsSL https://repo.waydro.id | sudo sh
sudo apt update
sudo apt install waydroid
```

The stock Debian kernel usually lacks `binder_linux`. Rebuild with
`sudo ./build.sh --custom-kernel` (the fragment enables
`CONFIG_ANDROID_BINDER_IPC` and `CONFIG_ANDROID_BINDERFS`) or install a
binder-enabled kernel/DKMS module. Without binder, the handler stops with a
clear message instead of failing halfway through an install.

Install and launch an APK:

```sh
sudo aether-apk ./app.apk
# or double-click the file
```

Waydroid uses Vanilla images by default. It does **not** bundle Google Play
services, ARM translation (`libndk`/`libhoudini`), or Widevine. ARM-only APKs
will install but not run. Multi-window mode is enabled by the setup script so
Android apps appear as floating labwc windows.

## iOS: IPA is inspection-only

There is no open-source iOS runtime for Linux. An `.ipa` contains a Mach-O
binary compiled for ARM64 iOS, signed by Apple, and dependent on UIKit,
Foundation, and Apple's frameworks. Running it requires a licensed iOS
environment. Corellium provides a commercial ARM virtualization service, but it
is not integrated into AetherOS and is not a local runtime.

What the handler does:

```sh
aether-ipa ./app.ipa
aether-ipa ./app.ipa --extract ./out
```

It lists the bundle identifier, version, architectures, size, and payload
files. This is useful for QA, malware triage, and asset inspection. It never
claims to launch the app.

## MIME integration

`config/compat/mime/aether-compat.xml` registers the types; `.desktop` files in
`overlay/usr/share/applications/` point at the handlers; `mimeapps.list` sets
defaults per user and system-wide. Rebuild the database after manual edits:

```sh
sudo update-mime-database /usr/share/mime
update-desktop-database ~/.local/share/applications
```

## Trust and safety

- `AETHER_TRUST=1` runs the handler without the confirmation prompt. Only use it
  in a disposable VM and only for files you obtained from a trusted source.
- Wine and Waydroid are not sandboxes. A Windows or Android app has the same
  access to your files as the user running it.
- Debian packages run maintainer scripts as root. Inspect unfamiliar `.deb`
  files with `dpkg-deb -I` and `dpkg-deb -c` before installing.
- The live image has passwordless sudo. The full installer replaces it with a
  password and removes the live sudoers file. Frugal installs keep the live
  autologin by design; change it if the machine is shared.

## Licensing and availability

Wine, Waydroid, Debian, Mesa, and GRUB are open source under their respective
licenses. macOS is not; Darling is an independent project. iOS is not; Corellium
is a commercial service. No proprietary Apple code or ARM translation library is
included in this repository or the ISO.
