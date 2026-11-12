"""Tests of e2e/fake_synthesis.py: the fake Opus of the E2E."""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "e2e"))
import fake_synthesis as fs

TEMPLATE = """# Research questions: {{GAME}}

### Q1.1 First?
Why we ask: x
- **Answer:** _(pending)_
- **Evidence:** _(pending)_

### Q1.2 Second?
- **Answer:** _(pending)_
"""


def _prompt(tmp: Path, *, finish: bool) -> Path:
    """A prompt file naming the template (and, for a finish, the markers)."""
    template = tmp / "docs" / "research" / "DOCS-research-questions.md"
    template.parent.mkdir(parents=True)
    template.write_text(TEMPLATE)
    prompt = tmp / "prompt.txt"
    prompt.write_text(
        f"Questions template: {template}\n"
        + ("MERGED ANSWERS and REPORT\n" if finish else "")
    )
    return prompt


def test_fill_adds_a_status_line_after_every_answer() -> None:
    doc = fs.fill(TEMPLATE)
    assert "_(pending)_" not in doc
    assert len(re.findall(r"^- \*\*Status:\*\* answered$", doc, re.MULTILINE)) == 2
    first = doc.splitlines()
    at = first.index("- **Answer:** e2e answer")
    assert first[at + 1] == "- **Status:** answered"


def test_a_session_synthesis_is_one_document(tmp_path: Path, capsys) -> None:
    assert fs.main(str(_prompt(tmp_path, finish=False))) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "@@@DOC"
    assert out[-1] == "@@@END"
    assert "@@@PL" not in out
    assert "@@@EN" not in out


def test_a_finish_answers_merged_and_report(tmp_path: Path, capsys) -> None:
    assert fs.main(str(_prompt(tmp_path, finish=True))) == 0
    out = capsys.readouterr().out.splitlines()
    assert out[0] == "@@@MERGED"
    assert "@@@REPORT" in out
    assert out[out.index("@@@TASK") + 1]
    assert out[out.index("@@@CHECK") + 1] == "true"
    assert out.index("@@@REPORT") < out.index("@@@TASK") < out.index("@@@CHECK")
    assert out[-1] == "@@@END"
    assert out[out.index("@@@REPORT") + 1].startswith("# ")


def test_a_prompt_without_a_template_is_exit_2(tmp_path: Path) -> None:
    prompt = tmp_path / "p.txt"
    prompt.write_text("nothing")
    assert fs.main(str(prompt)) == 2
