#!/usr/bin/env python3
"""Stands in for steam-backlog-enforcer's control socket in the E2E.

`fake_enforcer.py <sock> <log>` answers every JSON-line request with
`{"ok": true, "data": {}}` and appends the request to <log>, so a research
game add goes through without the real daemon (which would touch kuhy's
real enforcer state).
"""

from __future__ import annotations

import json
import socket
import sys
from pathlib import Path


def serve(path: Path, log: Path) -> None:
    """Answers requests on the socket at [path] until killed."""
    path.unlink(missing_ok=True)
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as srv:
        srv.bind(str(path))
        srv.listen()
        while True:
            conn, _ = srv.accept()
            with conn, conn.makefile("rwb") as stream:
                line = stream.readline()
                with log.open("ab") as out:
                    out.write(line)
                stream.write(json.dumps({"ok": True, "data": {}}).encode() + b"\n")
                stream.flush()


if __name__ == "__main__":
    serve(Path(sys.argv[1]), Path(sys.argv[2]))
