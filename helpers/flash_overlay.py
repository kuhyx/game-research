"""Marker confirmation: a coloured border flash around the game's output.

Started by the wrapper per session with the output's geometry; reads one
`#rrggbb` per line on stdin and shows four override-redirect edge strips in
that colour for --ms milliseconds. A line may carry a tag after the colour
(`#rrggbb tag`); once the strips are drawn the helper prints
`shown <tag> <unix wall time>` on stdout (the wrapper logs it as ground truth
for the marker-to-flash latency). Four strips, not one full-screen window:
without a compositor a full-screen window would cover the game. Exits on
stdin EOF, so it cannot outlive the wrapper. Never takes focus.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
import tkinter as tk

_HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def parse_geometry(text: str) -> tuple[int, int, int, int]:
    """(width, height, x, y) of a `WxH+X+Y` string."""
    m = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", text.strip())
    if m is None:
        msg = f"bad geometry: {text!r}"
        raise ValueError(msg)
    w, h, x, y = (int(g) for g in m.groups())
    return w, h, x, y


def strips(geometry: tuple[int, int, int, int], px: int) -> list[str]:
    """Tk geometry strings of the top, bottom, left and right edge strips."""
    w, h, x, y = geometry
    return [
        f"{w}x{px}+{x}+{y}",
        f"{w}x{px}+{x}+{y + h - px}",
        f"{px}x{h}+{x}+{y}",
        f"{px}x{h}+{x + w - px}+{y}",
    ]


def parse_colour(line: str) -> str | None:
    """The colour on one stdin line, or None for anything else."""
    text = line.strip()
    return text if _HEX.match(text) else None


def parse_line(line: str) -> tuple[str, str] | None:
    """(colour, tag) of one stdin line; the tag defaults to the hex digits."""
    parts = line.split()
    if not parts or len(parts) > 2:
        return None
    colour = parse_colour(parts[0])
    if colour is None:
        return None
    return colour, parts[1] if len(parts) == 2 else colour[1:]


class Flasher:
    """Four hidden strips that show a colour for a moment."""

    def __init__(
        self, root: tk.Tk, geometry: tuple[int, int, int, int], px: int, ms: int
    ) -> None:
        self.root = root
        self.ms = ms
        self.windows: list[tk.Toplevel] = []
        self.pending: str | None = None
        for geo in strips(geometry, px):
            win = tk.Toplevel(root)
            win.overrideredirect(True)
            win.geometry(geo)
            win.attributes("-topmost", True)
            win.withdraw()
            self.windows.append(win)

    def flash(self, colour: str, tag: str | None = None) -> None:
        """Shows `colour` on every strip, hides them after `ms`; prints
        `shown <tag> <unix time>` once the strips have been drawn."""
        if self.pending is not None:
            self.root.after_cancel(self.pending)
        for win in self.windows:
            win.configure(bg=colour)
            win.deiconify()
            win.lift()
        self.pending = self.root.after(self.ms, self.hide)
        self.root.update()  # map and paint now, not at the next idle
        shown = time.time()
        print(f"shown {tag or colour[1:]} {shown:.6f}", flush=True)

    def hide(self) -> None:
        """Hides every strip."""
        self.pending = None
        for win in self.windows:
            win.withdraw()


class StdinFeed:
    """Feeds complete stdin lines to the flasher from inside the Tk loop
    (a Tk file handler, so no second thread ever touches Tk)."""

    def __init__(self, root: tk.Tk, flasher: Flasher, fd: int) -> None:
        self.root = root
        self.flasher = flasher
        self.fd = fd
        self.buffer = b""
        self.busy = False

    def on_readable(self, *_: object) -> None:
        """Reads what arrived; flashes each complete line; quits on EOF."""
        if self.busy:  # flash() runs root.update(), which can re-enter here
            return
        self.busy = True
        try:
            self._read()
        finally:
            self.busy = False

    def _read(self) -> None:
        chunk = os.read(self.fd, 4096)
        if not chunk:
            self.root.tk.deletefilehandler(self.fd)
            self.root.destroy()
            return
        self.buffer += chunk
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            parsed = parse_line(line.decode("ascii", "replace"))
            if parsed is not None:
                self.flasher.flash(*parsed)


def main(argv: list[str] | None = None) -> int:
    """Runs the overlay until stdin closes."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--geometry", required=True)
    parser.add_argument("--thickness", type=int, default=12)
    parser.add_argument("--ms", type=int, default=300)
    args = parser.parse_args(argv)
    root = tk.Tk()
    root.withdraw()
    flasher = Flasher(root, parse_geometry(args.geometry), args.thickness, args.ms)
    feed = StdinFeed(root, flasher, sys.stdin.fileno())
    root.tk.createfilehandler(feed.fd, tk.READABLE, feed.on_readable)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
