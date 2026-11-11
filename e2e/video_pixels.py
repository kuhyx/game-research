"""One ffmpeg decode shared by check_session.py and tool/marker_lag.py."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


def border_pixels(
    video: Path, start: float, duration: float, y: int
) -> tuple[list[float], bytes]:
    """(pts seconds, rgb24 bytes) of the left-border pixel (x=4) of every frame
    in [start, start + duration]; pts are the file's own (-copyts)."""
    done = subprocess.run(
        ["ffmpeg", "-v", "info", "-hide_banner", "-copyts", "-ss", f"{start:.3f}",
         "-i", str(video), "-to", f"{start + duration:.3f}",
         "-vf", f"crop=1:1:4:{y},format=rgb24,showinfo",
         "-f", "rawvideo", "-"],
        capture_output=True, check=True, timeout=50,
    )  # fmt: skip
    times = [float(t) for t in re.findall(rb"pts_time:(-?[0-9.]+)", done.stderr)]
    return times, done.stdout
