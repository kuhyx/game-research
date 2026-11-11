"""One ffmpeg decode shared by check_session.py and tool/marker_lag.py."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


def border_pixels(
    video: Path, start: float, duration: float, y: int
) -> tuple[list[float], bytes]:
    """(absolute pts seconds, rgb24 bytes) of the left-border pixel (x=4) of
    every frame in [start, start + duration).

    A recording's start_time is not 0, so `-ss` must be absolute:
    `-seek_timestamp 1`. That does not combine with `-copyts` (ffmpeg then
    still drops frames before start + start_time), so the output pts are
    seek-relative and `start` is added back. The 2x2 crop precedes the rgb24
    conversion because a 1x1 crop of 4:2:0 video rounds to 0 wide."""
    done = subprocess.run(
        ["ffmpeg", "-v", "info", "-hide_banner",
         "-seek_timestamp", "1", "-ss", f"{start:.3f}", "-i", str(video),
         "-t", f"{duration:.3f}",
         "-vf", f"crop=2:2:4:{y},format=rgb24,crop=1:1:0:0,showinfo",
         "-f", "rawvideo", "-"],
        capture_output=True, check=True, timeout=50,
    )  # fmt: skip
    rel = [float(t) for t in re.findall(rb"pts_time:(-?[0-9.]+)", done.stderr)]
    # showinfo can log one frame the -t cut then drops: keep the delivered ones
    return [start + t for t in rel[: len(done.stdout) // 3]], done.stdout
