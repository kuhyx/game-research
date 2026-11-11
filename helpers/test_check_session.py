"""Tests of e2e/check_session.py's flash check on a synthetic video."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
import check_session as cs


def _video(tmp: Path, flash_at: float) -> Path:
    """A 5 s 64x64 video: black, then the `bad` red from `flash_at`."""
    video = tmp / "recording.mkv"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=black:64x64:r=30:d=5",
         "-f", "lavfi", "-i", "color=0xe2302f:64x64:r=30:d=5",
         "-filter_complex", f"[0][1]overlay=enable='gte(t,{flash_at})'",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(video)],
        check=True, timeout=30,
    )  # fmt: skip
    return tmp


def _run(session: Path, *, anywhere: bool) -> int:
    c = cs.Checker()
    markers = [{"tag": "bad", "offset_s": 1.0}]
    cs.check_flash(c, session, markers, anywhere=anywhere)
    return c.failed


def test_flash_late_in_the_window_passes_only_when_anywhere(tmp_path: Path) -> None:
    session = _video(tmp_path, flash_at=1.4)  # 0.4 s after the marker
    assert _run(session, anywhere=True) == 0
    assert _run(session, anywhere=False) == 1  # exact +0.15 sample is black


def test_flash_at_the_exact_sample_passes_both_ways(tmp_path: Path) -> None:
    session = _video(tmp_path, flash_at=1.1)
    assert _run(session, anywhere=True) == 0
    assert _run(session, anywhere=False) == 0


def test_flash_after_the_window_fails_anywhere(tmp_path: Path) -> None:
    session = _video(tmp_path, flash_at=2.0)  # 1.0 s after the marker
    assert _run(session, anywhere=True) == 1
