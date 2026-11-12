"""Tests of `install.sh --step resume`: the systemd user timer + service.

Renders the units into a scratch directory (never ~/.config, never systemctl)
and lets `systemd-analyze --user verify` judge them.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent


def _install(tmp: Path) -> Path:
    """Runs the resume step into `tmp/units`; returns that folder."""
    units = tmp / "units"
    env = {
        **os.environ,
        "GAME_RESEARCH_UNIT_DIR": str(units),
        "GAME_RESEARCH_NO_SYSTEMCTL": "1",
    }
    subprocess.run(
        [str(REPO / "install.sh"), "--step", "resume"],
        check=True, env=env, timeout=30, capture_output=True,
    )  # fmt: skip
    return units


def test_the_step_writes_a_timer_and_a_oneshot_service(tmp_path: Path) -> None:
    units = _install(tmp_path)
    timer = (units / "game-research-resume.timer").read_text()
    assert "OnBootSec=2min" in timer
    assert "OnUnitActiveSec=15min" in timer
    assert "WantedBy=timers.target" in timer
    service = (units / "game-research-resume.service").read_text()
    assert "Type=oneshot" in service
    assert "TimeoutStartSec=infinity" in service
    assert f"WorkingDirectory={REPO}" in service
    assert f"ExecStart={REPO}/build/analyze/bundle/bin/game_research_analyze" in service
    assert "--resume-all" in service
    # Never compete with a game, same as the launcher's systemd-run unit.
    for prop in ("Nice=19", "CPUSchedulingPolicy=idle", "IOSchedulingClass=idle"):
        assert prop in service
    # The user manager's PATH lacks ~/.local/bin (dart, claude).
    assert re.search(r"Environment=PATH=.*/\.local/bin:", service)
    assert not re.search(r"@[A-Z]+@", service)


def test_the_installer_is_idempotent(tmp_path: Path) -> None:
    first = _install(tmp_path)
    before = {p.name: p.read_text() for p in first.iterdir()}
    again = _install(tmp_path)
    assert {p.name: p.read_text() for p in again.iterdir()} == before


@pytest.mark.skipif(shutil.which("systemd-analyze") is None, reason="no systemd")
def test_systemd_accepts_the_units(tmp_path: Path) -> None:
    units = _install(tmp_path)
    # verify checks ExecStart exists and is executable: give it a stand-in.
    exe = Path(f"{REPO}/build/analyze/bundle/bin/game_research_analyze")
    made = not exe.exists()
    if made:
        exe.parent.mkdir(parents=True, exist_ok=True)
        exe.write_text("#!/bin/sh\n")
        exe.chmod(0o755)
    try:
        result = subprocess.run(
            ["systemd-analyze", "--user", "verify",
             str(units / "game-research-resume.service"),
             str(units / "game-research-resume.timer")],
            check=False, capture_output=True, text=True, timeout=30,
        )  # fmt: skip
    finally:
        if made:
            exe.unlink()
    assert result.returncode == 0, result.stderr
    assert result.stderr.strip() == "", result.stderr
