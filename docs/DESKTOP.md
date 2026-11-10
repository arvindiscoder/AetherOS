# AetherOS Glass Desktop

AetherOS uses labwc, Waybar, GTK, Mako, and a bundled SVG wallpaper. The theme
aims for the floating menu-bar and dock layout shown in the macOS reference
while keeping the existing Wayland session and low-overhead package set.

## Components

- `config/desktop/waybar/config.jsonc` defines the full-width menu bar, clock,
  workspaces, audio, network, Bluetooth, battery, brightness, and quick settings.
- `config/desktop/waybar/dock.jsonc` defines the centered launcher shelf and
  running-window taskbar.
- `config/desktop/waybar/style.css` defines translucent materials, edge lines,
  soft shadows, hover movement, icon sizing, and the rounded dock shape.
- `config/desktop/labwc/rc.xml` and `themerc` define rounded server-decorated
  windows and red, amber, and green window-control icons.
- `config/desktop/gtk-3.0/gtk.css` and `gtk-4.0/gtk.css` style GTK app headers,
  menus, popovers, buttons, and entries.
- `config/desktop/labwc/autostart` starts both bars and notifications.
- `overlay/usr/share/backgrounds/aether/liquid-glass.svg` supplies the original
  blue, violet, and coral wave background.
- `overlay/usr/local/bin/aether-control-center` opens the quick settings menu;
  `aether-bluetooth` provides the Bluetooth state and toggle used by Waybar.

## Rendering limits

CSS opacity, borders, and shadows style clients, but they do not sample or blur
the desktop behind them. Waybar requests the Wayland
`ext-background-effect-v1` blur protocol; labwc 0.8.3 does not implement that
protocol, so Waybar uses its translucent-color fallback. The wallpaper is
static, with no runtime tint sampling. The titlebar uses the native labwc close,
minimize, and maximize glyphs with traffic-light colors; labwc does not expose
custom traffic-light artwork or cursor-angle refraction shaders.

The menu bar offers Aether's system menu and status controls. Linux apps in this
stack do not provide a shared macOS-style global File/Edit/View menu, so the
bar does not display nonfunctional placeholder menus.

Real backdrop blur, dynamic wallpaper sampling, and refractive window edges
would require adding those effects to the compositor's rendering pipeline or
moving to a compositor that supports them. The current theme does not pretend
that CSS can provide those compositor-level effects.

Quick settings are on demand to preserve the low-overhead baseline. Idle RAM
still needs to be measured on the installed system and hardware.
