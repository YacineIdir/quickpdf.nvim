# Spike: terminal pixel geometry

Issue #14. To place the viewer on one Neovim window instead of the whole
terminal, the plugin needs the size of a cell in pixels and where the grid
starts inside the terminal window. This spike measures the candidate ways of
getting them.

Status: kitty and alacritty measured on 2026-11-18. foot and wezterm are not
installed on the test machine and still need a run (see
[Running it again](#running-it-again)).

## Setup

- Hyprland, one monitor `eDP-1` at 1920x1080, scale 1.
- Neovim 0.12.5, started as `nvim --clean` inside the terminal.
- kitty with the maintainer's config: `font_size 12`,
  `window_padding_width 8`. alacritty with no config file (defaults).
- Each terminal ran on a hidden special workspace, so the window was
  tiled but never shown.

Two probes, both in this directory:

- `pixel-geometry-raw.py` asks the terminal directly, without Neovim.
- `pixel-geometry-probe.lua` runs inside Neovim and tries every method a
  plugin could use.

## Results

Both terminal windows were 1876x1006 px, as reported by `hyprctl clients`.

| Measure                 | kitty        | alacritty    |
| ----------------------- | ------------ | ------------ |
| Grid (columns x lines)  | 206 x 51     | 208 x 55     |
| True cell size (px)     | 9 x 19       | 9 x 18       |
| `CSI 16 t`, raw         | 9 x 19       | no reply     |
| `CSI 14 t`, raw         | 1854 x 969   | 1872 x 990   |
| `CSI 16/14 t` in Neovim | swallowed    | swallowed    |
| TIOCGWINSZ pixels       | 1854 x 969   | 1872 x 990   |
| Window / grid (px)      | 9.11 x 19.73 | 9.02 x 18.29 |

### Terminal query through `TermResponse`

It does not work in Neovim 0.12.5. The TUI reads the replies to
`CSI 16 t` and `CSI 14 t` and drops them: `TermResponse` only fires for
DA1, OSC, DCS and APC replies, and nothing reaches `vim.on_key` either. The
only sequences the probe saw were replies to Neovim's own startup queries
(DA1, background colour, DSR). Even outside Neovim, alacritty does not answer
`CSI 16 t`; it answers `CSI 14 t` only.

### TIOCGWINSZ

It works in both terminals, and it is exact. Since Neovim 0.10 the Lua code
runs in a server process without a terminal. The TUI is its parent process,
and the TUI's stdin is the pty. The probe opens `/proc/<parent>/fd/0`
read-only and calls `ioctl(TIOCGWINSZ)` through LuaJIT's FFI. The pixel
fields always matched `columns x cell` and `lines x cell`, the same numbers
as `CSI 14 t`.

### Compositor rectangle divided by the grid

It answers everywhere Hyprland runs, but it includes the padding and the
pixels left over after the last full cell. The error per cell is small
(kitty: +0.11 px across, +0.73 px down), but it adds up over the grid. At the
last column and line it is off by the whole padding: 22 px and 37 px in
kitty, 4 px and 16 px in alacritty.

## Can the padding be derived?

The formula is `(window width - columns x cell width) / 2`, and the same
for height.

- kitty: yes, to within 0.5 px. kitty centres the grid by default
  (`placement_strategy center`). The formula gives 11 px across, which is
  `window_padding_width 8` in points (10.67 px, rounded). Down, it gives
  18.5 px: the 11 px padding plus half of the 15 px left over.
- alacritty: no. With the default `dynamic_padding = false`, alacritty
  draws the grid right after its padding (0 px by default) and leaves the
  rest at the right and bottom. The formula puts the grid 2 px and 8 px too
  far; it is only right with `dynamic_padding = true`.

So the grid origin depends on each terminal's placement rule, not only on
the numbers it reports.

## Recommendation

Cell size, in this order:

1. TIOCGWINSZ on the TUI's pty, when the server's parent process is an
   `nvim` whose stdin is a terminal and the pixel fields are not zero.
   Exact in every terminal measured so far.
2. The compositor rectangle divided by the grid, as a degraded mode. It is
   good enough to cover the whole terminal (today's behaviour), but not for
   placing the viewer on one window.
3. `CSI 16 t` through `TermResponse` once Neovim forwards CSI replies. It is
   not usable today, and alacritty would not answer it anyway.

Grid origin: take `(window - grid) / 2` for terminals known to centre the
grid (kitty), and `padding` at the top-left for terminals that do not
(alacritty, unless `dynamic_padding`). Until foot and wezterm are measured,
put this choice behind a per-terminal table keyed on `$TERM` or the window
class, with centring as the default.

Remote UIs (`nvim --remote-ui`, GUIs over `--embed`) have no TUI parent,
so only the compositor method is left for them.

Still open:

- foot and wezterm.
- A monitor with fractional scaling. Hyprland reports logical pixels, the
  terminal device pixels.

## Running it again

From the repository root, inside a Hyprland session. The window opens on a
hidden special workspace and closes when the probe ends:

```bash
out=/tmp/quickpdf-probe
mkdir -p "$out"
probe=$PWD/docs/spikes/pixel-geometry-probe.lua
raw=$PWD/docs/spikes/pixel-geometry-raw.py
hide='[workspace special:qpdfprobe silent]'
hyprctl dispatch exec "$hide env QUICKPDF_PROBE_OUT=$out/foot.json \
  foot nvim --clean -c 'luafile $probe'"
hyprctl dispatch exec "$hide env QUICKPDF_PROBE_OUT=$out/foot-raw.json \
  foot python3 -I $raw"
```

Replace `foot` with `wezterm start --`, `kitty` or `alacritty -e`.
