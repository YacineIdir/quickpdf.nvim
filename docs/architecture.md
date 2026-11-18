# Architecture

How quickpdf.nvim is put together. Terms are defined in
[GLOSSARY.md](../GLOSSARY.md); decisions and their reasons are in
[docs/adr/](adr/).

## Contents

- [Components](#components)
- [Opening a PDF](#opening-a-pdf)
- [Viewer lifecycle](#viewer-lifecycle)
- [Lua modules](#lua-modules)

## Components

Neovim owns the navigation state and decides what to show. The daemon owns
the viewer and renders pages. The compositor places the viewer.

```mermaid
flowchart LR
    %% Who talks to whom, and over what channel
    subgraph Neovim
        PB[PDF buffer<br/>navigation state]
    end
    subgraph Daemon[Daemon - Quickshell]
        V[Viewer window]
    end
    C[Compositor<br/>Hyprland]
    P[poppler<br/>pdftoppm, pdfinfo]

    PB -- "quickshell ipc call pdf ..." --> Daemon
    PB -- "hyprctl: geometry, move, focus" --> C
    PB -- "pdfinfo: page count" --> P
    Daemon -- "pdftoppm: render page PNG" --> P
    C -- "places" --> V
```

## Opening a PDF

```mermaid
sequenceDiagram
    title Opening a PDF, then turning a page
    participant N as Neovim
    participant D as Daemon
    participant C as Compositor

    N->>N: BufReadCmd *.pdf: placeholder text, page count
    N->>D: start if not answering IPC
    N->>C: geometry of the terminal
    N->>D: open(path, page, width)
    D->>D: render page at width x zoom
    N->>C: wait for the viewer, then move and resize it
    N->>C: focus the terminal again
    N->>D: key n: gotoPage(page, width)
    D->>D: render, merging fast repeated presses
```

## Viewer lifecycle

```mermaid
stateDiagram-v2
    %% State of the viewer as seen from Neovim
    [*] --> NoDaemon
    NoDaemon --> Visible: PDF buffer read or entered
    Visible --> Hidden: BufLeave on the PDF buffer
    Hidden --> Visible: BufEnter on the PDF buffer
    Visible --> WindowLost: viewer closed from the compositor
    WindowLost --> Visible: next show restarts the daemon
    Visible --> NoDaemon: VimLeavePre
    Hidden --> NoDaemon: VimLeavePre
```

## Lua modules

```mermaid
flowchart TD
    %% Arrows point from a module to the modules it requires
    init[init.lua<br/>setup, autocommands] --> viewer
    init --> config
    init --> daemon
    viewer[viewer.lua<br/>navigation state, actions] --> ui
    viewer --> daemon
    viewer --> hyprland
    viewer --> config
    ui[ui.lua<br/>placeholder, winbar, keymaps] --> config
    daemon[daemon.lua<br/>process lifecycle, IPC] --> config
    hyprland[hyprland.lua<br/>hyprctl calls]
    config[config.lua<br/>options]
```

`ui.lua` does not require `viewer.lua`: the viewer passes its actions to
`ui.keymaps()`, so there is no dependency cycle.
