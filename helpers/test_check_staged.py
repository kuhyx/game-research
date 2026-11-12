"""Tests of e2e/check_staged.py: the captioned-image judge of F5."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
import check_staged as cs


def _jpg(path: Path, size: tuple[int, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size).save(path)


def test_taller_staged_files_pass(tmp_path: Path) -> None:
    _jpg(tmp_path / "clips" / "m_01_good.jpg", (640, 360))
    _jpg(tmp_path / "s" / "01_good.jpg", (640, 420))
    _jpg(tmp_path / "s" / "02_bad.jpg", (640, 500))
    assert cs.judge(tmp_path / "s", tmp_path / "clips", 2) == []
    assert cs.main([str(tmp_path / "s"), str(tmp_path / "clips"), "2"]) == 0


def test_uncaptioned_wrong_count_and_stray_names_fail(tmp_path: Path, capsys) -> None:
    _jpg(tmp_path / "clips" / "m_01_good.jpg", (640, 360))
    _jpg(tmp_path / "s" / "01_good.jpg", (640, 360))
    _jpg(tmp_path / "s" / "m_01_good.jpg", (640, 400))
    broken = cs.judge(tmp_path / "s", tmp_path / "clips", 2)
    assert any("1 staged files, not 2" in b for b in broken)
    assert any("01_good.jpg is 640x360" in b for b in broken)
    assert cs.main([str(tmp_path / "s"), str(tmp_path / "clips"), "2"]) == 1
    assert "no band" in capsys.readouterr().err


def test_usage(tmp_path: Path) -> None:
    assert cs.main([]) == 2
