"""Spike #14: ask the terminal directly, without Neovim in between.

Sends CSI 16 t (cell size in px), CSI 14 t (text area in px), then DA1 as a
barrier every terminal answers, and writes the raw reply to
$QUICKPDF_PROBE_OUT as JSON. Run it as the terminal's only program:

    QUICKPDF_PROBE_OUT=/tmp/kitty-raw.json kitty python3 -I docs/spikes/pixel-geometry-raw.py
"""

import json
import os
import re
import select
import termios
import tty

out = os.environ["QUICKPDF_PROBE_OUT"]
fd = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
saved = termios.tcgetattr(fd)
tty.setraw(fd)
reply = b""
try:
    os.write(fd, b"\x1b[16t\x1b[14t\x1b[c")
    while select.select([fd], [], [], 1.0)[0]:
        reply += os.read(fd, 1024)
        if re.search(rb"\x1b\[\?[\d;]*c", reply):
            break
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, saved)

with open(out, "w") as f:
    json.dump({"raw": reply.decode("latin-1")}, f)
