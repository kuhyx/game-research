"""Fake Opus answer for the E2E: the template with every slot filled.

Reads the synthesis prompt file, finds the two template paths it names and
prints both between the @@@EN / @@@PL / @@@END marker lines with
`_(pending)_` replaced, so the wrapper's
parser and file writes run on a realistic answer.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_TEMPLATE = re.compile(r"(/\S+DOCS-research-questions(?:-pl)?\.md)")


def fill(template: str) -> str:
    """Fills the template's placeholders with fixed E2E text."""
    text = template.replace("{{GAME}}", "Dummy Game").replace("{{SESSION}}", "e2e")
    return text.replace("_(pending)_", "e2e answer")


def main(prompt_file: str) -> int:
    """Prints the fake synthesis answer; exit 2 when a template is missing."""
    prompt = Path(prompt_file).read_text(encoding="utf-8")
    paths = sorted(set(_TEMPLATE.findall(prompt)))
    en = [p for p in paths if not p.endswith("-pl.md")]
    pl = [p for p in paths if p.endswith("-pl.md")]
    if not en or not pl:
        print("templates not named in the prompt", file=sys.stderr)
        return 2
    print("@@@EN")
    print(fill(Path(en[0]).read_text(encoding="utf-8")))
    print("@@@PL")
    print(fill(Path(pl[0]).read_text(encoding="utf-8")))
    print("@@@END")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
