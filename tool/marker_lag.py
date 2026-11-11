#!/usr/bin/env python3
"""Marker flash lag: overlay draw time vs. when the recording shows it.

For each line of `<session>/flashes.jsonl` (written by the wrapper from the
overlay's `shown <tag> <unix>` output) this finds the first frame of
`recording.mkv` whose left-border pixel (x=4, y=height//2) has the tag's flash
colour, searching from 1.0 s before to 1.5 s after the draw time, and prints
`<tag> lag_s=<video time - expected time>`, then `mean= sd= n=`.

File time 0 is `t0_unix` of session.json (the finished, remuxed file). While
a session still records, gsr's raw file is unshifted: pass `--raw` to use
`recording.mkv.ts` (second line `monotonic_us<TAB>realtime_us`, the first
frame's wall clock) as file time 0 instead. Exit 1 when a flash is not found.
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
from check_session import FLASH, PIXEL_TOLERANCE, ffprobe
from video_pixels import border_pixels

BEFORE_S = 1.0
AFTER_S = 1.5


@dataclass(frozen=True)
class Flash:
    """One overlay draw: the marker tag and its wall-clock time."""

    tag: str
    shown_unix: float


def parse_flashes(text: str) -> list[Flash]:
    """The valid flashes of a flashes.jsonl text; malformed lines are skipped."""
    flashes: list[Flash] = []
    for line in text.splitlines():
        try:
            data = json.loads(line)
            tag, shown = data["tag"], data["shown_unix"]
        except (ValueError, KeyError, TypeError):
            continue
        if tag in FLASH and isinstance(shown, int | float):
            flashes.append(Flash(tag, float(shown)))
    return flashes


def parse_first_frame_realtime(text: str) -> float:
    """Unix seconds of the first frame, from the .ts file's second line."""
    lines = text.splitlines()
    if len(lines) < 2:
        msg = "no timestamp line in the .ts file"
        raise ValueError(msg)
    return int(lines[1].split("\t")[1]) / 1e6


def expected_time(shown_unix: float, t0_unix: float, raw_origin: float | None) -> float:
    """File time at which the flash was drawn (raw_origin: raw-file mode)."""
    return shown_unix - (t0_unix if raw_origin is None else raw_origin)


def search_window(expected: float) -> tuple[float, float]:
    """(start, duration) of the span searched around `expected`."""
    return max(0.0, expected - BEFORE_S), BEFORE_S + AFTER_S


def first_match(
    times: list[float], pixels: bytes, want: bytes, tolerance: int
) -> float | None:
    """Time of the first frame whose rgb24 pixel is within `tolerance`."""
    for i, t in enumerate(times):
        got = pixels[3 * i : 3 * i + 3]
        if len(got) == 3 and all(abs(a - b) <= tolerance for a, b in zip(got, want)):
            return t
    return None


def stats(lags: list[float]) -> tuple[float, float, int]:
    """(mean, population sd, n); zeros for no data."""
    if not lags:
        return 0.0, 0.0, 0
    return statistics.fmean(lags), statistics.pstdev(lags), len(lags)


def report(results: list[tuple[str, float | None]]) -> tuple[list[str], bool]:
    """Output lines and whether any flash was not found."""
    lines = [
        f"{tag} lag_s={'NOT_FOUND' if lag is None else f'{lag:.3f}'}"
        for tag, lag in results
    ]
    found = [lag for _, lag in results if lag is not None]
    mean, sd, n = stats(found)
    lines.append(f"mean={mean:.3f} sd={sd:.3f} n={n}")
    return lines, len(found) != len(results)


def measure(session: Path, raw: bool) -> list[tuple[str, float | None]]:
    """(tag, lag) per flash of the session; lag None when not found."""
    video = session / "recording.mkv"
    height = int(
        ffprobe("-show_streams", "-select_streams", "v", str(video))["streams"][0][
            "height"
        ]
    )
    t0 = 0.0
    origin: float | None = None
    if raw:
        origin = parse_first_frame_realtime((session / "recording.mkv.ts").read_text())
    else:
        t0 = float(json.loads((session / "session.json").read_text())["t0_unix"])
    flashes = parse_flashes((session / "flashes.jsonl").read_text())
    results: list[tuple[str, float | None]] = []
    for f in flashes:
        expected = expected_time(f.shown_unix, t0, origin)
        start, duration = search_window(expected)
        times, pixels = border_pixels(video, start, duration, height // 2)
        seen = first_match(times, pixels, bytes.fromhex(FLASH[f.tag]), PIXEL_TOLERANCE)
        lag = None if seen is None or math.isnan(seen) else seen - expected
        results.append((f.tag, lag))
    return results


def main() -> int:
    """Prints the lag per flash; exit 1 when any is not found."""
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("session", type=Path)
    p.add_argument("--raw", action="store_true", help="unshifted gsr file (.ts)")
    args = p.parse_args()
    lines, missing = report(measure(args.session, args.raw))
    print("\n".join(lines))
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
