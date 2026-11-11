"""Tests of tool/marker_lag.py: the parsing and lag arithmetic, plus one
decode of a tiny synthetic video (ffmpeg lavfi, no display)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tool"))
import marker_lag as ml


def test_parse_flashes_skips_malformed_lines() -> None:
    text = (
        '{"tag": "bad", "shown_unix": 100.5}\n'
        "\n"
        "not json\n"
        '{"tag": "good"}\n'
        '{"tag": "nope", "shown_unix": 1}\n'
        '{"tag": "note", "shown_unix": "x"}\n'
        '{"tag": "good", "shown_unix": 101}\n'
    )
    assert ml.parse_flashes(text) == [ml.Flash("bad", 100.5), ml.Flash("good", 101.0)]


def test_parse_first_frame_realtime_reads_second_line() -> None:
    text = "monotonic\trealtime\n5000000\t1700000002500000\n6000000\t1\n"
    assert ml.parse_first_frame_realtime(text) == 1700000002.5
    with pytest.raises(ValueError, match="no timestamp"):
        ml.parse_first_frame_realtime("only one line\n")


def test_expected_time_uses_t0_or_first_frame() -> None:
    assert ml.expected_time(110.25, 100.0, raw_origin=None) == 10.25
    assert ml.expected_time(110.25, 100.0, raw_origin=108.0) == 2.25


def test_search_window_is_1s_before_to_1_5s_after_and_clamped() -> None:
    assert ml.search_window(10.0) == (9.0, 2.5)
    assert ml.search_window(0.4) == (0.0, 2.5)


def test_first_match_returns_first_close_frame() -> None:
    want = bytes.fromhex("e2302f")
    pixels = bytes([0, 0, 0, 0xE0, 0x30, 0x30, 0xE2, 0x30, 0x2F])
    assert ml.first_match([1.0, 1.1, 1.2], pixels, want, 64) == 1.1
    assert ml.first_match([1.0, 1.1, 1.2], bytes(9), want, 64) is None


def test_stats_mean_and_population_sd() -> None:
    assert ml.stats([0.2, 0.4]) == pytest.approx((0.3, 0.1, 2))
    assert ml.stats([]) == (0.0, 0.0, 0)


def test_report_lines_and_missing_flag() -> None:
    lines, missing = ml.report([("bad", 0.25), ("good", None)])
    assert lines == [
        "bad lag_s=0.250",
        "good lag_s=NOT_FOUND",
        "mean=0.250 sd=0.000 n=1",
    ]
    assert missing is True


def _make_session(tmp: Path, t0: float, flash_at: float) -> Path:
    """A 5 s 64x64 video: black, then the `bad` red from `flash_at`."""
    video = tmp / "recording.mkv"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=black:64x64:r=30:d=5",
         "-f", "lavfi", "-i", "color=0xe2302f:64x64:r=30:d=5",
         "-filter_complex", f"[0][1]overlay=enable='gte(t,{flash_at})'",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", str(video)],
        check=True, timeout=30,
    )  # fmt: skip
    (tmp / "session.json").write_text(f'{{"t0_unix": {t0}}}')
    return tmp


def test_measure_session_end_to_end(tmp_path: Path) -> None:
    session = _make_session(tmp_path, 1000.0, flash_at=2.0)
    # Drawn at file time 1.8 s, seen in the video at 2.0 s: lag 0.2 s.
    (session / "flashes.jsonl").write_text('{"tag": "bad", "shown_unix": 1001.8}\n')
    results = ml.measure(session, raw=False)
    assert results[0][0] == "bad"
    lag = results[0][1]
    assert lag is not None
    assert lag == pytest.approx(0.2, abs=0.05)


def test_measure_raw_uses_first_frame_realtime(tmp_path: Path) -> None:
    session = _make_session(tmp_path, 0.0, flash_at=2.0)
    (session / "recording.mkv.ts").write_text("monotonic\trealtime\n1\t5000000000\n")
    (session / "flashes.jsonl").write_text('{"tag": "bad", "shown_unix": 5001.8}\n')
    lag = ml.measure(session, raw=True)[0][1]
    assert lag is not None
    assert lag == pytest.approx(0.2, abs=0.05)
