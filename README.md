# quickpdf.nvim

View PDFs from Neovim in a [Quickshell](https://quickshell.org) window that
overlays your terminal, positioned by Hyprland. Navigation (page, zoom, pan)
is driven entirely from Neovim keymaps — focus never leaves the terminal.

No in-buffer terminal graphics, so nothing flickers when the layout changes.

## Requirements

- Neovim ≥ 0.12 (uses `vim.pack` in the example; any plugin manager works)
- [Hyprland](https://hyprland.org)
- [Quickshell](https://quickshell.org) (`quickshell` / `qs` on `$PATH`)
- `poppler-utils` (`pdftoppm`, `pdfinfo`)

## Install

```lua
-- vim.pack
vim.pack.add({ "https://github.com/YacineIdir/quickpdf.nvim" })
require("quickpdf").setup()
```

```lua
-- lazy.nvim
{ "YacineIdir/quickpdf.nvim", opts = {} }
```

### Hyprland window rule (recommended)

Add this to `hyprland.conf` so the viewer floats and never takes keyboard
focus. Without it the plugin falls back to toggling float and re-asserting
focus a few times after the window maps, which usually works but can race.

```ini
windowrule {
    name = quickshell-pdf-viewer
    match:title = ^(quickshell-pdf-viewer)$

    float = yes
    no_focus = true
    no_shadow = true
}
```

Then `hyprctl reload`.

## Usage

Open any `.pdf` (`:e file.pdf`, or from a file explorer). The viewer appears
over the Neovim window with the same geometry. Leaving the buffer hides it,
coming back re-shows it, quitting Neovim stops the daemon.

Default keymaps in the PDF buffer (normal mode):

| Key   | Action              |
|-------|---------------------|
| `n`   | next page           |
| `p`   | previous page       |
| `z`   | zoom in             |
| `q`   | zoom out            |
| `e`   | reset zoom          |
| `h` `j` `k` `l` | pan       |

The winbar shows `page x/y` and zoom. Zooming keeps the visible region in
place; mouse wheel also pans the viewer.

## Configuration

Defaults:

```lua
require("quickpdf").setup({
    qs_config = nil,       -- dir containing shell.qml; defaults to the bundled one
    keymaps = {
        next_page = "n",
        prev_page = "p",
        zoom_in = "z",
        zoom_out = "q",
        zoom_reset = "e",
        pan_left = "h",
        pan_right = "l",
        pan_up = "k",
        pan_down = "j",
    },
    zoom_step = 0.1,
    min_zoom = 0.2,
    pan_fraction = 0.25,   -- fraction of the window moved per pan press
    winbar = true,
})
```

Set a keymap to `false` to disable it.

## How it works

- `BufReadCmd *.pdf` replaces the buffer with a placeholder and records
  page count (`pdfinfo`).
- A Quickshell daemon (`quickshell -p <plugin>/quickshell/pdf_viewer -d -n`)
  exposes an IPC target `pdf` with `open`, `gotoPage`, `pan`, `close`, `quit`.
- Neovim reads the focused terminal's geometry from `hyprctl activewindow`,
  tells Quickshell to show the page rendered at `terminal_width × zoom` px
  (`pdftoppm`), then moves/resizes the viewer onto the terminal and hands
  focus back.
- Each page flip / zoom is one IPC call; rapid presses are coalesced in QML.

## License

MIT
