"""Tests of the border flash helper. Tk parts run only under `xvfb-run -a`
(scripts/test.sh py), never on kuhy's display."""

from __future__ import annotations

import os
import tkinter as tk

import pytest

from helpers import flash_overlay as fo


def test_parse_geometry_reads_wxh_x_y() -> None:
    assert fo.parse_geometry("3840x2160+0+0") == (3840, 2160, 0, 0)
    with pytest.raises(ValueError, match="bad geometry"):
        fo.parse_geometry("3840x2160")


def test_strips_cover_the_four_edges() -> None:
    assert fo.strips((100, 50, 10, 20), 4) == [
        "100x4+10+20",
        "100x4+10+66",
        "4x50+10+20",
        "4x50+106+20",
    ]


def test_parse_colour_accepts_only_hex() -> None:
    assert fo.parse_colour("#3cb043\n") == "#3cb043"
    assert fo.parse_colour("green") is None


@pytest.fixture
def root() -> tk.Tk:
    if os.environ.get("DISPLAY", ":0") == ":0":
        pytest.skip("Tk tests run only on a private Xvfb (xvfb-run -a)")
    r = tk.Tk()
    r.withdraw()
    yield r
    r.destroy()


def test_flash_shows_then_hides(root: tk.Tk) -> None:
    flasher = fo.Flasher(root, (200, 100, 0, 0), 4, 50)
    flasher.flash("#e2302f")
    root.update()
    assert all(w.winfo_viewable() for w in flasher.windows)
    assert flasher.windows[0].cget("bg") == "#e2302f"
    flasher.flash("#3cb043")  # a second flash restarts the timer
    flasher.hide()
    root.update()
    assert not any(w.winfo_viewable() for w in flasher.windows)


def test_stdin_feed_flashes_lines_and_quits_on_eof(root: tk.Tk) -> None:
    flasher = fo.Flasher(root, (200, 100, 0, 0), 4, 50)
    read_fd, write_fd = os.pipe()
    feed = fo.StdinFeed(root, flasher, read_fd)
    os.write(write_fd, b"#2f6fe2\nnot a colour\n#f0c0")
    feed.on_readable()
    assert flasher.windows[0].cget("bg") == "#2f6fe2"
    assert feed.buffer == b"#f0c0"
    os.close(write_fd)
    destroyed: list[bool] = []
    root.destroy = lambda: destroyed.append(True)  # type: ignore[method-assign]
    root.tk.createfilehandler(read_fd, tk.READABLE, feed.on_readable)
    feed.on_readable()
    assert destroyed == [True]
    os.close(read_fd)
