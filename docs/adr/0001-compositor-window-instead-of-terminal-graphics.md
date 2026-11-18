# Show pages in a compositor window, not with terminal graphics

Pages are drawn by a separate Wayland window (the viewer) placed over the
terminal, instead of terminal graphics protocols such as kitty graphics
inside the buffer. Any Neovim layout change after an in-terminal image is
placed (winbar, `cmdheight`, number column) invalidates the placement and the
page disappears or flickers; a real window is unaffected.

## Consequences

- The plugin depends on a supported Wayland compositor and on Quickshell. It
  does not work over SSH, in a TTY or on X11.
- The viewer sits above the terminal, so Neovim floating windows and popup
  menus drawn over the PDF window are hidden behind it.
- Keyboard focus must be handed back to the terminal after the viewer
  appears.
