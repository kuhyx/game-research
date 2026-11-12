"""Tests of e2e/check_paste.py: decoding and judging a paste title."""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
import check_paste as cp


def _title(n: int, files: list[str], text: str) -> str:
    body = json.dumps({"files": len(files), "names": files, "text": text})
    return f"P{n}:" + base64.b64encode(body.encode()).decode()


def test_decode_reads_counter_and_utf8_body() -> None:
    n, paste = cp.decode(_title(3, ["a.jpg"], "zażółć 👍"))
    assert n == 3
    assert paste == {"files": 1, "names": ["a.jpg"], "text": "zażółć 👍"}


def test_decode_strips_the_browser_suffix() -> None:
    n, _ = cp.decode(_title(1, [], "x") + " - Chromium")
    assert n == 1


@pytest.mark.parametrize("title", ["paste-ready", "Px:abc", "P1:%%%", ""])
def test_decode_rejects_junk(title: str) -> None:
    with pytest.raises(ValueError):
        cp.decode(title)


def test_files_paste_passes_and_fails() -> None:
    names = [f"m_{i:02d}_good.jpg" for i in range(1, 9)]
    paste = {"files": 8, "names": names, "text": ""}
    assert cp.judge(paste, files=8, names=r"m_\d\d_\w+\.jpg") == []
    assert cp.judge(paste, files=7)[0].startswith("files: 8")
    assert "names" in cp.judge(paste, files=8, names=r"x_\d+")[0]


def test_text_rules() -> None:
    paste = {"files": 0, "names": [], "text": "**Game** · notes"}
    assert cp.judge(paste, files=0, text_prefix="**") == []
    assert cp.judge(paste, files=0, text_prefix="#")[0].startswith("text starts")
    assert cp.judge(paste, files=0, text_max=5)[0].startswith("text is 16")
    assert cp.judge({**paste, "text": "a|b"}, files=0, text_forbid="|")[0].startswith(
        "text has"
    )


def test_main_prints_json_and_exit_code(capsys: pytest.CaptureFixture[str]) -> None:
    title = _title(2, ["m_01_good.jpg"], "")
    assert cp.main(["--title", title, "--n", "2", "--files", "1"]) == 0
    assert json.loads(capsys.readouterr().out)["names"] == ["m_01_good.jpg"]
    assert cp.main(["--title", title, "--n", "3", "--files", "1"]) == 1
    assert cp.main(["--title", title, "--n", "2", "--files", "2"]) == 1
    assert cp.main(["--title", "junk", "--n", "1", "--files", "0"]) == 1
