"""Decode and judge what e2e/paste_page.html saw in a paste (F5).

The page writes `P<n>:<base64 of {"files", "names", "text"}>` into its window
title; `xdotool getwindowname` reads it back. Prints the decoded JSON and
exits 0 when every given rule holds, else prints the broken rules to stderr
and exits 1.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import re
import sys

_TITLE = re.compile(r"^P(\d+):([A-Za-z0-9+/=]+)(?: - .*)?$")


def decode(title: str) -> tuple[int, dict]:
    """The paste counter and the paste a window title carries."""
    m = _TITLE.match(title.strip())
    if m is None:
        raise ValueError(f"not a paste title: {title[:60]!r}")
    try:
        body = base64.b64decode(m[2], validate=True).decode()
    except (binascii.Error, UnicodeDecodeError) as e:
        raise ValueError(f"undecodable paste title: {e}") from e
    return int(m[1]), json.loads(body)


def judge(
    paste: dict,
    *,
    files: int,
    names: str | None = None,
    text_prefix: str | None = None,
    text_max: int | None = None,
    text_forbid: str | None = None,
    ordered: bool = False,
) -> list[str]:
    """Every rule `paste` breaks (empty = good)."""
    broken: list[str] = []
    text = paste["text"]
    if paste["files"] != files:
        broken.append(f"files: {paste['files']} != {files}")
    if names is not None:
        bad = [n for n in paste["names"] if not re.fullmatch(names, n)]
        if bad:
            broken.append(f"names do not match {names}: {bad}")
    if ordered:
        # Discord pairs images with note lines by order alone.
        want = [f"{i:02d}_" for i in range(1, len(paste["names"]) + 1)]
        if [n[:3] for n in paste["names"]] != want:
            broken.append(
                f"names not numbered 01_, 02_, ... in order: {paste['names']}"
            )
    if text_prefix is not None and not text.startswith(text_prefix):
        broken.append(f"text starts {text[:20]!r}, not {text_prefix!r}")
    if text_max is not None and len(text) > text_max:
        broken.append(f"text is {len(text)} chars > {text_max}")
    if text_forbid is not None and text_forbid in text:
        broken.append(f"text has {text_forbid!r}")
    return broken


def main(argv: list[str] | None = None) -> int:
    """CLI: judge one title."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--title", required=True)
    ap.add_argument("--n", type=int, required=True, help="expected paste counter")
    ap.add_argument("--files", type=int, required=True)
    ap.add_argument("--names")
    ap.add_argument("--text-prefix")
    ap.add_argument("--text-max", type=int)
    ap.add_argument("--text-forbid")
    ap.add_argument(
        "--ordered", action="store_true", help="names are 01_, 02_, ... in order"
    )
    args = ap.parse_args(argv)
    try:
        n, paste = decode(args.title)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 1
    print(json.dumps(paste, ensure_ascii=False))
    broken = judge(
        paste,
        files=args.files,
        names=args.names,
        text_prefix=args.text_prefix,
        text_max=args.text_max,
        text_forbid=args.text_forbid,
        ordered=args.ordered,
    )
    if n != args.n:
        broken.append(f"paste counter {n} != {args.n}")
    for why in broken:
        print(why, file=sys.stderr)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
