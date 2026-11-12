"""Judge the staged, captioned images of a files copy (F5).

Usage: check_staged.py STAGED_DIR CLIPS_DIR COUNT

Every `NN_<tag>.jpg` in STAGED_DIR must be the full-width still with a band
added below it: same width as a `m_*.jpg` in CLIPS_DIR, at least MIN_BAND px
taller. Prints what it saw; exits 0 when all COUNT files are captioned, 1
with the broken rules on stderr otherwise.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image

MIN_BAND = 20
_STAGED = re.compile(r"\d{2,}_(good|bad|confusing|note)\.jpg")


def judge(staged: Path, clips: Path, count: int) -> list[str]:
    """Every rule the staged folder breaks (empty = good)."""
    stills = {Image.open(f).size for f in sorted(clips.glob("m_*.jpg"))}
    files = sorted(f for f in staged.glob("*.jpg") if _STAGED.fullmatch(f.name))
    broken: list[str] = []
    if len(files) != count:
        broken.append(f"{len(files)} staged files, not {count}")
    for f in files:
        w, h = Image.open(f).size
        if not any(w == sw and h >= sh + MIN_BAND for sw, sh in stills):
            broken.append(f"{f.name} is {w}x{h}: no band below any still {stills}")
    return broken


def main(argv: list[str] | None = None) -> int:
    """CLI."""
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3:
        print("usage: check_staged.py STAGED_DIR CLIPS_DIR COUNT", file=sys.stderr)
        return 2
    broken = judge(Path(args[0]), Path(args[1]), int(args[2]))
    for why in broken:
        print(why, file=sys.stderr)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
