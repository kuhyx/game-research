"""Shared bits of the E2E session checks."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


def ffprobe(*args: str) -> dict:
    """Runs ffprobe with JSON output."""
    done = subprocess.run(
        ["ffprobe", "-v", "error", "-of", "json", *args],
        capture_output=True, text=True, check=True, timeout=30,
    )  # fmt: skip
    return json.loads(done.stdout)


def jsonl(path: Path) -> list[dict]:
    """Every non-blank line of a JSONL file."""
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


class Checker:
    """Collects failures instead of stopping at the first."""

    def __init__(self) -> None:
        self.failed = 0

    def check(self, name: str, ok: bool, why: str = "") -> None:
        """Records one check."""
        if ok:
            print(f"ok   {name}")
        else:
            self.failed += 1
            print(f"FAIL {name}: {why}")
