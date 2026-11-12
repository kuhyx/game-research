"""Tests of the still captioner (pure Pillow, no display)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

from helpers import caption_still as cs

W, H = 1600, 900


def make_job(tmp_path: Path, **over: str) -> dict:
    src = tmp_path / "in.jpg"
    Image.new("RGB", (W, H), (200, 30, 30)).save(src, "JPEG", quality=95)
    job = {
        "src": str(src),
        "out": str(tmp_path / "out" / "o.jpg"),
        "tag": "good",
        "time": "0:01:05",
        "note": "nice shelf",
        "right": "Librarian · 2026-11-10",
    }
    job.update(over)
    return job


def test_band_is_added_below_and_game_pixels_stay(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    cs.render(job)
    out = Image.open(job["out"])
    assert out.width == W
    assert out.height > H
    assert out.getpixel((W // 2, H // 2))[0] > 150  # still untouched
    assert sum(out.getpixel((W - 5, H + 5))) < 120  # dark band


@pytest.mark.parametrize("tag", ["good", "bad", "confusing", "note"])
def test_emoji_is_colour_not_tofu(tag: str) -> None:
    img = cs.emoji_image(tag, 60)
    assert img.size == (60, 60)
    saturated = [
        p
        for p in img.convert("RGBA").getdata()
        if p[3] > 200 and max(p[:3]) - min(p[:3]) > 60
    ]
    assert len(saturated) > 200


def test_note_wraps_to_two_lines_with_ellipsis() -> None:
    draw = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    font = cs.text_font(30)
    short = cs.wrap(draw, "two words", font, 900)
    assert short == ["two words"]
    long = cs.wrap(draw, "word " * 80, font, 400)
    assert len(long) == 2
    assert long[-1].endswith("…")
    assert draw.textlength(long[-1], font=font) <= 400
    assert cs.wrap(draw, "x" * 200, font, 300)[-1].endswith("…")


def test_empty_note_and_no_right_text_still_render(tmp_path: Path) -> None:
    job = make_job(tmp_path, note="", right="")
    cs.render(job)
    assert Image.open(job["out"]).height > H


def test_quality_92_jpeg(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    cs.render(job)
    img = Image.open(job["out"])
    assert img.format == "JPEG"
    # luminance table of quality 92: first entry is 5 (libjpeg scale 16)
    assert img.quantization[0][0] == 3


def test_main_renders_jobs_file_and_checks_usage(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    jobs = tmp_path / "jobs.json"
    jobs.write_text(json.dumps([job]), encoding="utf-8")
    assert cs.main([str(jobs)]) == 0
    assert Path(job["out"]).exists()
    assert cs.main([]) == 2
