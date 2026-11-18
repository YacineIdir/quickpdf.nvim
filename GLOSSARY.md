# quickpdf.nvim

Reading PDFs from Neovim in a separate window that the compositor lays
exactly over the part of the screen where Neovim shows the PDF.

See [docs/architecture.md](docs/architecture.md) for diagrams of how these
terms relate.

## Language

### Inside Neovim

**PDF buffer**:
The Neovim buffer opened on a `.pdf` file. It holds a read-only placeholder
text and the navigation state of that document, never the page itself.
_Avoid_: PDF file (that is the file on disk), document buffer

**PDF window**:
A Neovim window that displays a PDF buffer. The viewer covers it.
_Avoid_: split, pane

**Navigation state**:
The current page, page count and zoom of one PDF buffer. Neovim owns it; the
viewer only reflects it.
_Avoid_: view state, viewer state

### Outside Neovim

**Viewer**:
The window that displays the rendered page over the PDF window.
_Avoid_: overlay, popup, preview window

**Daemon**:
The long-running Quickshell process that owns the viewer and renders pages.
There is one per Neovim instance.
_Avoid_: server, backend, Quickshell instance

**Terminal**:
The compositor window that hosts the Neovim instance.
_Avoid_: host window, kitty window

**Compositor**:
The Wayland compositor that positions the viewer and gives keyboard focus
back to the terminal. Hyprland, Sway and niri are the targeted ones.
_Avoid_: window manager, WM
