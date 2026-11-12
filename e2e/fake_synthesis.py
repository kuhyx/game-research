"""Fake Opus answer for the E2E: the template with every slot filled.

Reads the prompt file, finds the template path it names and prints the filled
template between marker lines (`@@@DOC` ... `@@@END` for a session, or
`@@@MERGED` ... `@@@REPORT` ... `@@@END` for a finish), with `_(pending)_`
replaced and a `- **Status:** answered` line after every Answer line, so the
analyzer's parser, status-line check and file writes run on a realistic answer.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

_TEMPLATE = re.compile(r"(/\S+DOCS-research-questions\.md)")


def fill(template: str) -> str:
    """Fills the template's placeholders and adds the status lines."""
    text = template.replace("{{GAME}}", "Dummy Game").replace("{{SESSION}}", "e2e")
    text = text.replace("_(pending)_", "e2e answer")
    return re.sub(
        r"^(- \*\*Answer:\*\* .*)$",
        r"\1\n- **Status:** answered",
        text,
        flags=re.MULTILINE,
    )


def main(prompt_file: str) -> int:
    """Prints the fake answer; exit 2 when the template is not named."""
    prompt = Path(prompt_file).read_text(encoding="utf-8")
    found = _TEMPLATE.findall(prompt)
    if not found:
        print("template not named in the prompt", file=sys.stderr)
        return 2
    doc = fill(Path(found[0]).read_text(encoding="utf-8"))
    if "MERGED ANSWERS" in prompt:
        print("@@@MERGED")
        print(doc)
        print("@@@REPORT")
        print("# Dummy Game: what kuhy learned")
        print("e2e report")
    else:
        print("@@@DOC")
        print(doc)
    print("@@@END")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
