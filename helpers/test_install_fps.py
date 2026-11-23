"""Tests of `install.sh --step fps`: MangoHud for games only, never session-wide.

Runs the step with HOME, XDG_CONFIG_HOME and the data dir in a scratch folder,
and fake `pacman` / `systemctl` first on PATH (never the real ones).
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ENV_FILE = ".config/environment.d/60-game-research-mangohud.conf"
OLD_BLOCK = (
    "# >>> game-research mangohud >>>\n"
    "export MANGOHUD=1\n"
    "export MANGOHUD_CONFIGFILE=/x/mangohud.conf\n"
    "# <<< game-research mangohud <<<\n"
)


def _fake_bin(tmp: Path) -> Path:
    """`pacman` that says installed, `systemctl` that logs its arguments."""
    fake = tmp / "bin"
    fake.mkdir()
    (fake / "pacman").write_text("#!/bin/sh\nexit 0\n")
    (fake / "systemctl").write_text(f'#!/bin/sh\necho "$*" >>"{tmp}/systemctl.log"\n')
    for exe in fake.iterdir():
        exe.chmod(0o755)
    return fake


def _install(tmp: Path) -> subprocess.CompletedProcess[str]:
    home = tmp / "home"
    home.mkdir(exist_ok=True)
    fake = tmp / "bin" if (tmp / "bin").exists() else _fake_bin(tmp)
    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "GAME_RESEARCH_DATA": str(home / "data"),
        "PATH": f"{fake}:{os.environ['PATH']}",
    }
    return subprocess.run(
        [str(REPO / "install.sh"), "--step", "fps"],
        check=True, env=env, timeout=30, capture_output=True, text=True,
    )  # fmt: skip


def _old_install(home: Path) -> None:
    """What the session-wide installer left behind."""
    env_file = home / ENV_FILE
    env_file.parent.mkdir(parents=True)
    env_file.write_text("MANGOHUD=1\nMANGOHUD_CONFIGFILE=/x/mangohud.conf\n")
    (home / ".xprofile").write_text(f"xset s off\n{OLD_BLOCK}setxkbmap pl\n")


def test_the_old_session_wide_setup_is_removed(tmp_path: Path) -> None:
    home = tmp_path / "home"
    home.mkdir()
    _old_install(home)
    _install(tmp_path)
    assert not (home / ENV_FILE).exists()
    assert (home / ".xprofile").read_text() == "xset s off\nsetxkbmap pl\n"
    log = (tmp_path / "systemctl.log").read_text()
    assert "--user unset-environment MANGOHUD MANGOHUD_CONFIGFILE" in log
    # The environment.d generator's copy survives unset-environment: only a
    # reload (generators rerun without the file) drops it.
    assert "--user daemon-reload" in log
    assert "set-environment MANGOHUD" not in log.replace("unset-", "")
    conf = (home / "data" / "mangohud.conf").read_text()
    assert f"output_folder={home / 'data' / 'fps-spool'}\n" in conf


def test_no_xprofile_is_created_and_a_rerun_changes_nothing(tmp_path: Path) -> None:
    home = tmp_path / "home"
    _install(tmp_path)
    assert not (home / ".xprofile").exists()
    assert not (home / ENV_FILE).exists()
    before = sorted(str(p) for p in home.rglob("*"))
    _install(tmp_path)
    assert sorted(str(p) for p in home.rglob("*")) == before


def test_the_installer_never_turns_the_layer_on() -> None:
    live = [
        line
        for line in (REPO / "install.sh").read_text().splitlines()
        if re.match(r"^[^#]*MANGOHUD=1", line)
    ]
    assert live == []
