"""Marker confirmation: a coloured border flash around the game's output.

Started by the wrapper per session with the output's geometry; reads one
`#rrggbb` per line on stdin and shows four override-redirect edge strips in
that colour for --ms milliseconds. Four strips, not one full-screen window:
without a compositor a full-screen window would cover the game. Exits on
stdin EOF, so it cannot outlive the wrapper. Never takes focus.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
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

    def flash(self, colour: str) -> None:
        """Shows `colour` on every strip, hides them after `ms`."""
        if self.pending is not None:
            self.root.after_cancel(self.pending)
        for win in self.windows:
            win.configure(bg=colour)
            win.deiconify()
            win.lift()
        self.pending = self.root.after(self.ms, self.hide)

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

    def on_readable(self, *_: object) -> None:
        """Reads what arrived; flashes each complete line; quits on EOF."""
        chunk = os.read(self.fd, 4096)
        if not chunk:
            self.root.tk.deletefilehandler(self.fd)
            self.root.destroy()
            return
        self.buffer += chunk
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            colour = parse_colour(line.decode("ascii", "replace"))
            if colour is not None:
                self.flasher.flash(colour)


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
