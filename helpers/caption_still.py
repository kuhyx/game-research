"""Add a dark band with kuhy's note BELOW marker stills (no game pixel is covered).

Usage: caption_still.py JOBS.json

JOBS.json is a list of {"src", "out", "note", ...}; other keys are ignored.
The band holds only the note, whole, left aligned, wrapped over as many lines
as it needs (the band grows with the note). Font and padding scale with the
image width so it reads at Discord preview size. Output is JPEG quality 92.
Exit 0 when every job was written.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

TEXT_FONTS = (
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
)
BG = (24, 26, 31)
FG = (236, 234, 233)
QUALITY = 92
LINE_GAP = 1.25  # line height / font size


def text_font(size: int) -> ImageFont.FreeTypeFont:
    """The first available text font at `size` px."""
    for path in TEXT_FONTS:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size)  # pragma: no cover


def break_word(
    draw: ImageDraw.ImageDraw, word: str, font: ImageFont.FreeTypeFont, width: int
) -> list[str]:
    """`word` cut into pieces that each fit `width` px (a piece has >= 1 char)."""
    pieces: list[str] = []
    cur = ""
    for ch in word:
        if cur and draw.textlength(cur + ch, font=font) > width:
            pieces.append(cur)
            cur = ch
        else:
            cur += ch
    return [*pieces, cur]


def wrap(
    draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int
) -> list[str]:
    """Every word of `text`, in lines of at most `width` px (nothing is cut)."""
    lines: list[str] = []
    cur = ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if draw.textlength(trial, font=font) <= width:
            cur = trial
            continue
        if cur:
            lines.append(cur)
        *head, cur = break_word(draw, word, font, width)
        lines.extend(head)
    if cur:
        lines.append(cur)
    return lines


def render(job: dict) -> None:
    """Write the captioned copy of one still."""
    src = Image.open(job["src"]).convert("RGB")
    w, h = src.size
    unit = max(w // 40, 18)  # font px; 4K -> 96, 1080p -> 48
    pad = unit // 2
    font = text_font(unit)
    measure = ImageDraw.Draw(src)
    lines = wrap(measure, job.get("note", ""), font, w - 2 * pad)
    step = round(unit * LINE_GAP)
    band = len(lines) * step + 2 * pad
    out = Image.new("RGB", (w, h + band), BG)
    out.paste(src, (0, 0))
    draw = ImageDraw.Draw(out)
    for k, line in enumerate(lines):
        draw.text((pad, h + pad + k * step), line, font=font, fill=FG)
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
