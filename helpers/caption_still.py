"""Add a dark note band BELOW marker stills (no game pixel is covered).

Usage: caption_still.py JOBS.json

JOBS.json is a list of {"src", "out", "tag", "time", "note", "right"}.
Left of the band: the tag emoji in colour, the time, kuhy's note (at most
two lines, ellipsis beyond). Right: smaller, muted `right` text. The band
scales with the image width so it reads at Discord preview size. Output is
JPEG quality 92. Exit 0 when every job was written, else 1.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

EMOJI = {
    "good": "\U0001f44d",
    "bad": "\U0001f44e",
    "confusing": "❓",
    "note": "\U0001f4dd",
}
EMOJI_FONT = "/usr/share/fonts/noto/NotoColorEmoji.ttf"
TEXT_FONTS = (
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
)
BG = (24, 26, 31)
FG = (236, 234, 233)
MUTED = (150, 154, 162)
QUALITY = 92
BITMAP_PX = 109  # the only size the CBDT colour emoji font loads at


def text_font(size: int) -> ImageFont.FreeTypeFont:
    """The first available text font at `size` px."""
    for path in TEXT_FONTS:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)  # pragma: no cover


def emoji_image(tag: str, px: int) -> Image.Image:
    """The colour emoji of `tag` as a square RGBA image `px` wide."""
    font = ImageFont.truetype(EMOJI_FONT, BITMAP_PX)
    canvas = Image.new("RGBA", (BITMAP_PX + 40, BITMAP_PX + 40), (0, 0, 0, 0))
    ImageDraw.Draw(canvas).text((10, 10), EMOJI[tag], font=font, embedded_color=True)
    box = canvas.getbbox() or (0, 0, 1, 1)
    return canvas.crop(box).resize((px, px), Image.Resampling.LANCZOS)


def wrap(
    draw: ImageDraw.ImageDraw,
    text: str,
    font: ImageFont.FreeTypeFont,
    width: int,
    lines: int = 2,
) -> list[str]:
    """`text` as at most `lines` lines of `width` px; the last ends in an ellipsis."""
    words = text.split()
    out: list[str] = []
    cur = ""
    for i, word in enumerate(words):
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=font) <= width or not cur:
            cur = trial
            continue
        out.append(cur)
        cur = word
        if len(out) == lines - 1:
            cur = " ".join(words[i:])
            break
    out.append(cur)
    last = out[-1]
    if draw.textlength(last, font=font) > width:
        while last and draw.textlength(last + "…", font=font) > width:
            last = last[:-1]
        out[-1] = last.rstrip() + "…"
    return out


def render(job: dict) -> None:
    """Write the captioned copy of one still."""
    src = Image.open(job["src"]).convert("RGB")
    w, h = src.size
    unit = max(w // 40, 18)  # font px; 4K -> 96, 1080p -> 48
    pad = unit // 2
    band = unit * 3 + pad * 2
    out = Image.new("RGB", (w, h + band), BG)
    out.paste(src, (0, 0))
    draw = ImageDraw.Draw(out)
    big, small = text_font(unit), text_font(max(unit * 2 // 3, 12))
    icon = emoji_image(job["tag"], int(unit * 1.4))
    out.paste(icon, (pad, h + (band - icon.height) // 2), icon)
    x = pad + icon.width + pad
    time = job.get("time", "")
    draw.text((x, h + band // 2), time, font=big, fill=FG, anchor="lm")
    x += int(draw.textlength(time, font=big)) + pad * 2
    right = job.get("right", "")
    rw = int(draw.textlength(right, font=small)) if right else 0
    room = w - x - pad - (rw + pad * 2 if rw else 0)
    note = " ".join(job.get("note", "").split())
    lines = wrap(draw, note, big, max(room, unit)) if note else []
    top = h + (band - len(lines) * unit * 1.25) / 2
    for k, line in enumerate(lines):
        draw.text((x, top + k * unit * 1.25), line, font=big, fill=FG)
    if right:
        draw.text((w - pad, h + band // 2), right, font=small, fill=MUTED, anchor="rm")
    Path(job["out"]).parent.mkdir(parents=True, exist_ok=True)
    out.save(job["out"], "JPEG", quality=QUALITY)


def main(argv: list[str] | None = None) -> int:
    """Render every job of the JSON file in argv[0]."""
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: caption_still.py JOBS.json", file=sys.stderr)
        return 2
    for job in json.loads(Path(args[0]).read_text(encoding="utf-8")):
        render(job)
    return 0


if __name__ == "__main__":
    sys.exit(main())
