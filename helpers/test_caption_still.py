"""Tests of the still captioner (pure Pillow, no display)."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw

from helpers import caption_still as cs

W, H = 1600, 900


def make_job(tmp_path: Path, **over: str) -> dict:
    src = tmp_path / "in.jpg"
    Image.new("RGB", (W, H), (200, 30, 30)).save(src, "JPEG", quality=95)
    job = {
        "src": str(src),
        "out": str(tmp_path / "out" / "o.jpg"),
        "note": "nice shelf",
    }
    job.update(over)
    return job


def band_height(job: dict) -> int:
    cs.render(job)
    return Image.open(job["out"]).height - H


def test_band_is_added_below_and_game_pixels_stay(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    cs.render(job)
    out = Image.open(job["out"])
    assert out.width == W
    assert out.height > H
    assert out.getpixel((W // 2, H // 2))[0] > 150  # still untouched
    assert sum(out.getpixel((W - 5, out.height - 5))) < 120  # dark band
    # the note is drawn: light pixels in the band
    band = out.crop((0, H, W, out.height))
    assert any(sum(p) > 500 for p in band.get_flattened_data())


def test_band_grows_with_the_note_and_nothing_is_cut(tmp_path: Path) -> None:
    short = band_height(make_job(tmp_path, note="short"))
    words = " ".join(f"word{k}" for k in range(120))
    long_job = make_job(tmp_path, note=words)
    assert band_height(long_job) > short * 3
    draw = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    font = cs.text_font(max(W // 40, 18))
    lines = cs.wrap(draw, words, font, W - W // 40)
    assert " ".join(lines).split() == words.split()
    assert not any("…" in ln for ln in lines)
    assert all(draw.textlength(ln, font=font) <= W - W // 40 for ln in lines)


def test_a_word_wider_than_the_band_is_broken_not_cut() -> None:
    draw = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    font = cs.text_font(30)
    lines = cs.wrap(draw, "ab " + "x" * 200 + " cd", font, 300)
    assert "".join(lines).replace(" ", "") == "ab" + "x" * 200 + "cd"
    assert all(draw.textlength(ln, font=font) <= 300 for ln in lines)


def test_empty_note_gives_only_padding(tmp_path: Path) -> None:
    assert 0 < band_height(make_job(tmp_path, note="")) < 60


def test_quality_92_jpeg(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    cs.render(job)
    img = Image.open(job["out"])
    assert img.format == "JPEG"
    assert img.quantization[0][0] == 3  # luminance table of quality 92


def test_main_renders_jobs_file_and_checks_usage(tmp_path: Path) -> None:
    job = make_job(tmp_path)
    jobs = tmp_path / "jobs.json"
    jobs.write_text(json.dumps([job]), encoding="utf-8")
    assert cs.main([str(jobs)]) == 0
    assert Path(job["out"]).exists()
    assert cs.main([]) == 2
