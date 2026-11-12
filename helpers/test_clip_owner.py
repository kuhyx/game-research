"""Tests of the clipboard owner helper. The X parts run only on a private
Xvfb (`xvfb-run -a`, scripts/test.sh py), never on kuhy's display."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

import pytest

from helpers import clip_owner as co

HELPER = Path(co.__file__).resolve()
# The helper needs PyGObject: the system python, not a venv's.
SYSTEM_PYTHON = "/usr/bin/python3"


def test_file_uri_is_absolute_and_percent_encoded(tmp_path: Path) -> None:
    f = tmp_path / "a b.jpg"
    f.write_bytes(b"x")
    assert co.file_uri(str(f)) == f"file://{tmp_path}/a%20b.jpg"


def test_payloads_offer_files_and_text_targets(tmp_path: Path) -> None:
    f = tmp_path / "a.jpg"
    f.write_bytes(b"x")
    data = co.payloads([str(f)], "héllo")
    uri = f"file://{tmp_path}/a.jpg"
    assert data[co.URI_LIST] == f"{uri}\r\n".encode()
    assert data[co.GNOME_FILES] == f"copy\n{uri}".encode()
    for name in co.TEXT_TARGETS:
        assert data[name] == "héllo".encode()


def test_payloads_omit_what_is_empty() -> None:
    assert set(co.payloads([], "t")) == set(co.TEXT_TARGETS)
    assert set(co.payloads(["/x/a.jpg"], "")) == {co.URI_LIST, co.GNOME_FILES}
    assert co.payloads([], "") == {}


def test_refuse_live_display_only_in_test_mode() -> None:
    assert co.refuse_live_display(":0", True)
    assert co.refuse_live_display(":0.0", True)
    assert co.refuse_live_display("", True)
    assert not co.refuse_live_display(":147", True)
    assert not co.refuse_live_display(":0", False)


def _run(args: list[str], env: dict[str, str]) -> subprocess.Popen[str]:
    return subprocess.Popen(
        [SYSTEM_PYTHON, str(HELPER), *args],
        env={**os.environ, **env},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_refuses_display_0_in_test_mode_before_touching_it() -> None:
    p = _run(["--text-file", "/dev/null"], {"DISPLAY": ":0", "GAME_RESEARCH_TEST": "1"})
    _, err = p.communicate(timeout=20)
    assert p.returncode == 2
    assert "refusing" in err


def test_nothing_to_offer_is_an_error() -> None:
    p = _run([], {"DISPLAY": ":147", "GAME_RESEARCH_TEST": "1"})
    _, err = p.communicate(timeout=20)
    assert p.returncode == 2
    assert "nothing" in err


def _private_display() -> str:
    display = os.environ.get("DISPLAY", ":0")
    if display.split(".")[0] == ":0":
        pytest.skip("X tests run only on a private Xvfb (xvfb-run -a)")
    return display


def test_unreachable_display_exits_3() -> None:
    _private_display()
    p = _run(
        ["--text-file", "/dev/null", "/x/a.jpg"],
        {"DISPLAY": ":198", "GAME_RESEARCH_TEST": "1"},
    )
    p.communicate(timeout=30)
    assert p.returncode == co.NO_DISPLAY


def _clip(display: str, target: str) -> bytes:
    return subprocess.run(
        ["xclip", "-o", "-selection", "clipboard", "-t", target],
        env={**os.environ, "DISPLAY": display},
        capture_output=True,
        check=True,
        timeout=10,
    ).stdout


def test_owns_clipboard_serves_every_target_and_quits_when_taken(
    tmp_path: Path,
) -> None:
    display = _private_display()
    jpg = tmp_path / "m_01_good.jpg"
    jpg.write_bytes(b"\xff\xd8jpeg")
    text = tmp_path / "t.txt"
    text.write_text("my note ✓\nline 2", encoding="utf-8")
    p = _run(
        ["--text-file", str(text), str(jpg)],
        {"DISPLAY": display, "GAME_RESEARCH_TEST": "1"},
    )
    try:
        assert p.stdout is not None
        assert p.stdout.readline().strip() == "ready"
        targets = _clip(display, "TARGETS").decode().split()
        for want in (
            co.URI_LIST,
            co.GNOME_FILES,
            "text/plain",
            "UTF8_STRING",
        ):
            assert want in targets
        uri = f"file://{jpg}"
        assert _clip(display, co.URI_LIST).decode().split() == [uri]
        assert _clip(display, co.GNOME_FILES).decode() == f"copy\n{uri}"
        assert _clip(display, "text/plain").decode() == "my note ✓\nline 2"
        assert _clip(display, "UTF8_STRING").decode() == "my note ✓\nline 2"
        # Another client takes the selection: the helper must quit by itself.
        taker = subprocess.Popen(
            ["xclip", "-i", "-selection", "clipboard"],
            env={**os.environ, "DISPLAY": display},
            stdin=subprocess.PIPE,
        )
        assert taker.stdin is not None
        taker.stdin.write(b"other")
        taker.stdin.close()
        deadline = time.monotonic() + 10
        while p.poll() is None and time.monotonic() < deadline:
            time.sleep(0.1)
        assert p.returncode == 0
        taker.terminate()
        taker.wait(timeout=5)
    finally:
        if p.poll() is None:
            p.kill()
        p.communicate()
