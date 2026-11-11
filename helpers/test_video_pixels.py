"""Tests of e2e/video_pixels.py on a synthetic video whose start_time is not 0
(like a real recording: the first frame sits at the recorder start-up delay)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
from video_pixels import border_pixels

START = 1.3


def _video(tmp: Path) -> Path:
    """4 s 64x64 at 10 fps: black for 2 s, then red; first pts is START."""
    video = tmp / "recording.mkv"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i",
         ("color=black:64x64:r=10:d=2[a];color=red:64x64:r=10:d=2[b];"
          "[a][b]concat=n=2:v=1:a=0"),
         "-output_ts_offset", str(START), "-c:v", "libx264", "-pix_fmt", "yuv420p",
         str(video)],
        check=True, timeout=30,
    )  # fmt: skip
    return video


def _start_time(video: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=start_time",
         "-of", "default=nw=1:nk=1", str(video)],
        check=True, capture_output=True, text=True, timeout=30,
    )  # fmt: skip
    return float(out.stdout)


def test_window_is_on_the_absolute_timeline(tmp_path: Path) -> None:
    video = _video(tmp_path)
    assert _start_time(video) > 1.0, "the fixture must not start at 0"
    times, px = border_pixels(video, 3.0, 0.8, 32)
    assert times, "no frames: -ss was read as start-relative"
    assert all(3.0 - 0.01 <= t < 3.8 + 0.01 for t in times)
    assert len(px) == 3 * len(times)
    # the cut is at 2 + START = 3.3: black before it, red after it
    first, last = px[:3], px[-3:]
    assert max(first) < 40
    assert last[0] > 180 and last[1] < 80 and last[2] < 80
