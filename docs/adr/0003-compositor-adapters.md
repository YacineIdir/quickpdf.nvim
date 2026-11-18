---
status: accepted
---

# One adapter per compositor behind a small interface

Hyprland, Sway and niri are supported through one adapter each, selected at
runtime from the environment (`HYPRLAND_INSTANCE_SIGNATURE`, `SWAYSOCK`,
`NIRI_SOCKET`) or forced with the `compositor` option. The rest of the plugin
only uses three operations: get the terminal's rectangle, place the viewer
on a rectangle, and focus a window.

The interface is extracted when the Sway adapter is written, not before:
with Hyprland alone there is nothing to vary across it, so the current
`hyprland.lua` stays a plain module until then.

Accepted on 2026-11-17, not implemented yet.
