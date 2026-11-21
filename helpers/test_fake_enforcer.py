"""e2e/fake_enforcer.py: answers every socket op with ok and logs it."""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
from pathlib import Path

FAKE = Path(__file__).resolve().parent.parent / "e2e" / "fake_enforcer.py"


def test_answers_ok_and_logs(tmp_path: Path) -> None:
    """One JSON line in, `{"ok": true}` back, the request in the log."""
    sock, log = tmp_path / "ctl.sock", tmp_path / "ops.log"
    proc = subprocess.Popen([sys.executable, str(FAKE), str(sock), str(log)])
    try:
        for _ in range(100):
            if sock.exists():
                break
            time.sleep(0.02)
        request = {"op": "research_game", "args": {"app_id": 7}}
        with socket.socket(socket.AF_UNIX) as client:
            client.connect(str(sock))
            client.sendall(json.dumps(request).encode() + b"\n")
            reply = client.makefile("rb").readline()
        assert json.loads(reply) == {"ok": True, "data": {}}
        assert json.loads(log.read_text()) == request
    finally:
        proc.kill()
        proc.wait()
