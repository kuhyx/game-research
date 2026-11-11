"""Asserts one finished E2E session (F1). Exit 0 = every check passed.

`--finished` only answers whether the analysis job has stopped (exit 0/1).
Each failed check prints one `FAIL <check>: <why>` line; the exit code is the
number of failed checks (capped at 100), so the step that failed is named.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from video_pixels import border_pixels

# Flash colours, the same as MarkerTag.flashHex in lib/core/markers.dart.
FLASH = {"good": "3cb043", "bad": "e2302f", "confusing": "f0c020", "note": "2f6fe2"}
TOLERANCE_S = 0.5
PIXEL_TOLERANCE = 64
WINDOW_S = 0.6  # --flash-only: the flash may land this long after the marker


def ffprobe(*args: str) -> dict:
    """Runs ffprobe with JSON output."""
    done = subprocess.run(
        ["ffprobe", "-v", "error", "-of", "json", *args],
        capture_output=True, text=True, check=True, timeout=30,
    )  # fmt: skip
    return json.loads(done.stdout)


def jsonl(path: Path) -> list[dict]:
    """Every non-blank line of a JSONL file."""
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def pixel(video: Path, t: float, x: int, y: int) -> tuple[int, int, int]:
    """RGB of one pixel of the frame at `t` seconds."""
    done = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", f"{t:.3f}", "-i", str(video), "-frames:v", "1",
         "-vf", f"crop=2:2:{x}:{y}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True, timeout=30,
    )  # fmt: skip
    r, g, b = done.stdout[:3]
    return r, g, b


def close_to(got: bytes, want: bytes) -> bool:
    """Whether every channel of `got` is within PIXEL_TOLERANCE of `want`."""
    return len(got) == len(want) and all(
        abs(a - b) <= PIXEL_TOLERANCE for a, b in zip(got, want, strict=True)
    )


class Checker:
    """Collects failures instead of stopping at the first."""

    def __init__(self) -> None:
        self.failed = 0

    def check(self, name: str, ok: bool, why: str = "") -> None:
        """Records one check."""
        if ok:
            print(f"ok   {name}")
        else:
            self.failed += 1
            print(f"FAIL {name}: {why}")


def check_markers(c: Checker, session: Path, art: Path, expect: int) -> list[dict]:
    """markers.jsonl against fired.jsonl and the MKV's chapters."""
    meta = json.loads((session / "session.json").read_text())
    markers = sorted(jsonl(session / "markers.jsonl"), key=lambda m: m["offset_s"])
    fired = sorted(jsonl(art / "fired.jsonl"), key=lambda f: f["wall"])
    c.check("marker count", len(markers) == expect, f"{len(markers)} != {expect}")
    c.check("fired count", len(fired) == expect, f"{len(fired)} != {expect}")
    t0 = float(meta["t0_unix"])
    for i, (m, f) in enumerate(zip(markers, fired, strict=False)):
        lo, hi = f["wall"] - t0 - TOLERANCE_S, f["after"] - t0 + TOLERANCE_S
        c.check(f"marker {i} tag", m["tag"] == f["tag"], f"{m['tag']} != {f['tag']}")
        c.check(
            f"marker {i} offset",
            lo <= m["offset_s"] <= hi,
            f"{m['offset_s']} not in [{lo:.3f}, {hi:.3f}]",
        )
    notes = {m.get("note", "") for m in markers}
    c.check("notes", {"hotkey note", "button note"} <= notes, f"notes {notes}")
    chapters = ffprobe("-show_chapters", str(session / "recording.mkv"))["chapters"]
    c.check("chapter count", len(chapters) == expect, f"{len(chapters)} chapters")
    for i, (ch, m) in enumerate(zip(chapters, markers, strict=False)):
        start = float(ch["start_time"])
        c.check(
            f"chapter {i} start",
            abs(start - m["offset_s"]) < 0.01,
            f"{start} vs {m['offset_s']}",
        )
        c.check(
            f"chapter {i} title",
            ch["tags"]["title"].startswith(m["tag"]),
            ch["tags"]["title"],
        )
    return markers


def check_flash(
    c: Checker, session: Path, markers: list[dict], anywhere: bool = False
) -> None:
    """The border flash shows in the recording at each marker's offset: the
    exact +0.15 s sample, or (`anywhere`) any frame in [offset, offset + 0.6]."""
    video = session / "recording.mkv"
    height = int(
        ffprobe("-show_streams", "-select_streams", "v", str(video))["streams"][0][
            "height"
        ]
    )
    for i, m in enumerate(markers):
        want = bytes.fromhex(FLASH[m["tag"]])
        if anywhere:
            times, px = border_pixels(video, m["offset_s"], WINDOW_S, height // 2)
            hits = [
                t
                for k, t in enumerate(times)
                if m["offset_s"] <= t <= m["offset_s"] + WINDOW_S
                and close_to(px[3 * k : 3 * k + 3], want)
            ]
            c.check(f"flash {i} {m['tag']}", bool(hits), f"no frame in {WINDOW_S} s")
            continue
        got = pixel(video, m["offset_s"] + 0.15, 4, height // 2)
        c.check(f"flash {i} {m['tag']}", close_to(bytes(got), want), f"pixel {got}")


def check_analysis(c: Checker, session: Path, expect: int) -> None:
    """Stage outputs: frames, clips, contact sheet, stills, captions."""
    a = session / "analysis"
    status = json.loads((a / "status.json").read_text())
    c.check("status done", status["state"] == "done", json.dumps(status))
    frames = json.loads((a / "frames.json").read_text())
    c.check(
        "marker frames",
        sum(f["kind"] == "marker" for f in frames) == expect,
        "marker frames",
    )
    missing = [f["file"] for f in frames if not (a / "frames" / f["file"]).is_file()]
    c.check("frame files", not missing and len(frames) > expect, f"missing {missing}")
    width = ffprobe("-show_streams", str(a / "frames" / frames[0]["file"]))["streams"][
        0
    ]["width"]
    c.check("frame width", int(width) <= 1280, f"width {width}")
    clips = sorted((a / "clips").glob("*.mkv"))
    c.check("clips", len(clips) == expect, f"{len(clips)} clips")
    for clip in clips:
        d = float(
            ffprobe("-show_entries", "format=duration", str(clip))["format"]["duration"]
        )
        c.check(f"clip {clip.name} length", 1.0 <= d <= 11.6, f"{d} s")
    c.check("contact sheet", any((a / "contact").glob("*.png")), "no contact/*.png")
    c.check("scenes", (a / "scenes.json").is_file(), "no scenes.json")
    stills = jsonl(a / "still.jsonl")
    c.check("still stretch", len(stills) >= 1, "no still span found")
    captions = jsonl(a / "captions.jsonl")
    c.check(
        "captions per frame",
        len(captions) == len(frames),
        f"{len(captions)} vs {len(frames)}",
    )
    c.check(
        "caption tier",
        all(x.get("model") == "fake:omniroute" for x in captions),
        "model",
    )
    c.check(
        "haiku skipped",
        all(any(s.startswith("haiku") for s in x["skipped"]) for x in captions),
        "skipped",
    )


def check_outputs(c: Checker, art: Path, expect: int) -> None:
    """Drafts in the scratch target, the todo call, ticks."""
    research = art / "target" / "docs" / "research"
    for name in ("DOCS-research-dummy-game.md", "DOCS-research-dummy-game-pl.md"):
        doc = research / name
        ok = (
            doc.is_file()
            and "_(pending)_" not in doc.read_text()
            and "e2e answer" in doc.read_text()
        )
        c.check(f"draft {name}", ok, "missing or unfilled")
    todo = (art / "todo.log").read_text() if (art / "todo.log").is_file() else ""
    c.check(
        "todo task",
        "review Dummy Game research draft" in todo and "--new-note" in todo,
        todo[:200],
    )
    ticks = (
        (art / "tick.log").read_text().splitlines()
        if (art / "tick.log").is_file()
        else []
    )
    c.check("ticks", len(ticks) == expect, f"{len(ticks)} ticks")
    llm = (art / "llm.log").read_text().splitlines()
    c.check(
        "one opus call", sum(line.startswith("opus") for line in llm) == 1, "opus calls"
    )


def main() -> int:
    """Parses arguments and runs the checks."""
    p = argparse.ArgumentParser()
    p.add_argument("--session", type=Path, required=True)
    p.add_argument("--art", type=Path)
    p.add_argument("--expect-markers", type=int, default=8)
    p.add_argument("--finished", action="store_true")
    # A real play session (no fired.jsonl): only the border flash at each
    # marker offset, the direct check of the gpu-screen-recorder time shift.
    p.add_argument("--flash-only", action="store_true")
    args = p.parse_args()
    status_file = args.session / "analysis" / "status.json"
    if args.finished:
        state = (
            json.loads(status_file.read_text())["state"]
            if status_file.is_file()
            else ""
        )
        return 0 if state in ("done", "failed") else 1
    c = Checker()
    if args.flash_only:
        markers = jsonl(args.session / "markers.jsonl")
        check_flash(c, args.session, markers, anywhere=True)
        return min(c.failed, 100)
    markers = check_markers(c, args.session, args.art, args.expect_markers)
    check_flash(c, args.session, markers)
    check_analysis(c, args.session, args.expect_markers)
    check_outputs(c, args.art, args.expect_markers)
    return min(c.failed, 100)


if __name__ == "__main__":
    sys.exit(main())
