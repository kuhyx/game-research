"""The E2E's stand-in game: one full-screen Tk window on the private Xvfb.

Started by fake_steam.sh as `dummy_game.py AppId=<id> --life <s>`, so its
command line carries the token the wrapper's process watcher looks for. The
picture changes in hard cuts (scene detection), has a motionless stretch
(still detection) and a moving bar otherwise. Exits after --life seconds.
"""

from __future__ import annotations

import argparse
import time
import tkinter as tk

# (seconds from start, background colour); after the last entry it loops.
_SCHEDULE: tuple[tuple[float, str], ...] = (
    (0.0, "#802020"),
    (3.0, "#203080"),
    (6.0, "#207040"),
    (9.0, "#806020"),
    (13.0, "#606060"),  # still from 13 s to 30 s: no bar is drawn
    (30.0, "#702070"),
)
_STILL = (13.0, 30.0)
_LOOP_S = 40.0
_TICK_MS = 50


def colour_at(elapsed: float) -> str:
    """Background colour at `elapsed` seconds into the loop."""
    t = elapsed % _LOOP_S
    current = _SCHEDULE[0][1]
    for start, colour in _SCHEDULE:
        if t >= start:
            current = colour
    return current


def is_still(elapsed: float) -> bool:
    """Whether the bar is hidden (the motionless stretch)."""
    t = elapsed % _LOOP_S
    return _STILL[0] <= t < _STILL[1]


def main() -> None:
    """Runs the window until --life seconds have passed."""
    parser = argparse.ArgumentParser()
    parser.add_argument("appid")
    parser.add_argument("--life", type=float, default=600.0)
    args = parser.parse_args()
    root = tk.Tk()
    width, height = root.winfo_screenwidth(), root.winfo_screenheight()
    root.geometry(f"{width}x{height}+0+0")
    root.overrideredirect(True)
    canvas = tk.Canvas(root, width=width, height=height, highlightthickness=0)
    canvas.pack()
    bar = canvas.create_rectangle(
        0, height // 2 - 40, 120, height // 2 + 40, fill="#e0e0e0"
    )
    start = time.monotonic()

    def tick() -> None:
        elapsed = time.monotonic() - start
        if elapsed >= args.life:
            root.destroy()
            return
        canvas.configure(bg=colour_at(elapsed))
        x = int((elapsed * 300) % width)
        canvas.coords(bar, x, height // 2 - 40, x + 120, height // 2 + 40)
        canvas.itemconfigure(bar, state="hidden" if is_still(elapsed) else "normal")
        root.after(_TICK_MS, tick)

    tick()
    root.mainloop()


if __name__ == "__main__":
    main()
