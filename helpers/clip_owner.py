"""Own the X11 CLIPBOARD with files and text, for pasting into Vesktop.

Usage: clip_owner.py [--text-file F] FILE...

Owns CLIPBOARD with the targets text/uri-list, x-special/gnome-copied-files
(`copy\\nfile:///...`), text/plain, text/plain;charset=utf-8, UTF8_STRING
and STRING. The text comes from --text-file (UTF-8). Prints `ready` on
stdout once it owns the selection; exits when another client takes the
selection (selection-clear). Never takes focus (hidden widget, never shown).
Refuses DISPLAY :0 while GAME_RESEARCH_TEST=1 (exit 2); exit 3 when the
display cannot be opened.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from urllib.parse import quote

NO_DISPLAY = 3  # exit code: the display cannot be opened
URI_LIST = "text/uri-list"
GNOME_FILES = "x-special/gnome-copied-files"
TEXT_TARGETS = ("text/plain", "text/plain;charset=utf-8", "UTF8_STRING", "STRING")


def file_uri(path: str) -> str:
    """`file://` URI of an absolute path, percent-encoded."""
    return "file://" + quote(str(Path(path).resolve()))


def payloads(files: list[str], text: str) -> dict[str, bytes]:
    """Target name -> bytes served for it (empty files/text omit targets)."""
    out: dict[str, bytes] = {}
    uris = [file_uri(f) for f in files]
    if uris:
        out[URI_LIST] = ("\r\n".join(uris) + "\r\n").encode()
        out[GNOME_FILES] = ("copy\n" + "\n".join(uris)).encode()
    if text:
        for name in TEXT_TARGETS:
            out[name] = text.encode()
    return out


def refuse_live_display(display: str, test_mode: bool) -> bool:
    """True when test mode would touch the real display :0."""
    return test_mode and display.split(".")[0] in (":0", "")


def main(argv: list[str] | None = None) -> int:
    """Own the clipboard until someone else takes it."""
    ap = argparse.ArgumentParser()
    ap.add_argument("--text-file")
    ap.add_argument("files", nargs="*")
    args = ap.parse_args(argv)
    display = os.environ.get("DISPLAY", "")
    if refuse_live_display(display, os.environ.get("GAME_RESEARCH_TEST") == "1"):
        print("refusing display :0 in test mode", file=sys.stderr)
        return 2
    text = Path(args.text_file).read_text(encoding="utf-8") if args.text_file else ""
    data = payloads(args.files, text)
    if not data:
        print("nothing to offer", file=sys.stderr)
        return 2

    # Importing Gtk opens the display, so only after the :0 refusal above.
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, Gtk

    if Gdk.Display.get_default() is None:
        print(f"cannot open display {display!r}", file=sys.stderr)
        return NO_DISPLAY
    win = Gtk.Window()
    win.realize()  # a realized, never shown window owns the selection
    clip_atom = Gdk.SELECTION_CLIPBOARD
    for name in data:
        Gtk.selection_add_target(win, clip_atom, Gdk.Atom.intern(name, False), 0)

    def on_get(_w, sel, _info: int, _time: int) -> None:
        payload = data.get(sel.get_target().name())
        if payload is not None:
            sel.set(sel.get_target(), 8, payload)

    def on_clear(_w, _event) -> bool:
        Gtk.main_quit()
        return True

    win.connect("selection-get", on_get)
    win.connect("selection-clear-event", on_clear)
    if not Gtk.selection_owner_set_for_display(
        win.get_display(), win, clip_atom, Gdk.CURRENT_TIME
    ):
        print("could not own the clipboard", file=sys.stderr)
        return 1
    print("ready", flush=True)
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
