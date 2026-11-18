---
status: accepted
---

# Test against fake executables on PATH, not injected functions

Unit tests replace `hyprctl`, `quickshell` and `pdfinfo` with small scripts
placed first on `PATH` that record their arguments and print canned output.
Production code keeps calling the real program names and has no injection
point for its process runner.

Injecting the runner would only prove that "some command was run"; the fake
executables check the exact command line the real tool receives, and need no
change to production code. What fakes cannot cover, `shell.qml` and the real
IPC, is covered by an end-to-end job running Quickshell under headless Sway.

Accepted on 2026-11-17, implemented by the `make test` harness
(`tests/fakes/`, `tests/helpers.lua`).
