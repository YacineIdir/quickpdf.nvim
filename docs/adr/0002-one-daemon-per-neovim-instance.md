---
status: accepted
---

# One daemon per Neovim instance

Each Neovim instance starts and stops its own daemon, with its own
Quickshell config path and render cache, instead of sharing one daemon
between all instances. A shared daemon made instances interfere: starting a
viewer or quitting Neovim killed the other instance's viewer, and both wrote
to the same cached page. Isolation costs one Quickshell process per Neovim
that has opened a PDF.

Accepted on 2026-11-17, implemented in `daemon.lua`. Quickshell tells
instances apart by config path, so each instance links the configured config
into Neovim's temp dir, next to its render cache, and finds its viewer window
by its daemon's pid, since every viewer has the title the window rule
matches.
