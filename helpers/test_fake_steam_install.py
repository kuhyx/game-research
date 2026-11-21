"""e2e/fake_steam.sh `steam://install/<id>`: a staged install the picker can show.

The wrapper reads Steam's appmanifest: StateFlags 1026 with BytesDownloaded <
BytesToDownload is an install in progress (the tile's ring), StateFlags 4 is
installed. The fake must pass through both so the E2E can see the ring.
"""

from __future__ import annotations

import os
import re
import subprocess
import time
from pathlib import Path

FAKE = Path(__file__).resolve().parent.parent / "e2e" / "fake_steam.sh"
APP = 4197610


def _field(text: str, key: str) -> str:
    """The value of one top-level `"key" "value"` line of a manifest."""
    match = re.search(rf'"{key}"\s+"([^"]*)"', text)
    assert match, f"{key} missing in manifest"
    return match.group(1)


def test_install_shows_progress_then_installs(tmp_path: Path) -> None:
    """The manifest first reports a partial download, then StateFlags 4."""
    (tmp_path / "install_s").write_text("2")
    (tmp_path / "install_name").write_text("Librarian")
    # No DISPLAY: a fake that wrongly ran the dummy game must not reach :0.
    env = {**os.environ, "GAME_RESEARCH_E2E_ART": str(tmp_path), "DISPLAY": ""}
    acf = tmp_path / "steam" / "steamapps" / f"appmanifest_{APP}.acf"
    proc = subprocess.Popen([str(FAKE), f"steam://install/{APP}"], env=env)
    seen_partial = False
    deadline = time.monotonic() + 10
    while proc.poll() is None and time.monotonic() < deadline:
        if acf.exists():
            text = acf.read_text()
            if _field(text, "StateFlags") == "1026":
                done = int(_field(text, "BytesDownloaded"))
                seen_partial |= 0 < done < int(_field(text, "BytesToDownload"))
        time.sleep(0.05)
    if proc.poll() is None:
        proc.kill()
    assert proc.wait(timeout=5) == 0
    text = acf.read_text()
    assert seen_partial
    assert _field(text, "StateFlags") == "4"
    assert _field(text, "name") == "Librarian"
    assert (tmp_path / "steam.log").read_text().strip() == f"steam://install/{APP}"
    assert not (tmp_path / "game.pid").exists()
