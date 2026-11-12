"""The analysis half of the E2E session checks: stage outputs, draft, todo."""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

from check_common import Checker, ffprobe, jsonl


def check_analysis(c: Checker, session: Path, expect: int) -> None:
    """Stage outputs: frames, clips, contact sheet, stills, captions."""
    a = session / "analysis"
    status = json.loads((a / "status.json").read_text())
    c.check("status done", status["state"] == "done", json.dumps(status))
    c.check(
        "status fields",
        {"tokens", "cost_usd", "eta_s", "started_unix"} <= status.keys()
        and set(status["tokens"]) == {"in", "out", "cache_read", "cache_write"},
        json.dumps(status),
    )
    frames = json.loads((a / "frames.json").read_text())
    c.check(
        "marker frames",
        sum(f["kind"] == "marker" for f in frames) == expect,
        "marker frames",
    )
    missing = [f["file"] for f in frames if not (a / "frames" / f["file"]).is_file()]
    c.check("frame files", not missing and len(frames) > expect, f"missing {missing}")
    width = ffprobe("-show_streams", str(a / "frames" / frames[0]["file"]))["streams"][
        0
    ]["width"]
    c.check("frame width", int(width) <= 1280, f"width {width}")
    clips = sorted((a / "clips").glob("*.mkv"))
    c.check("clips", len(clips) == expect, f"{len(clips)} clips")
    for clip in clips:
        d = float(
            ffprobe("-show_entries", "format=duration", str(clip))["format"]["duration"]
        )
        c.check(f"clip {clip.name} length", 1.0 <= d <= 11.6, f"{d} s")
    c.check("contact sheet", any((a / "contact").glob("*.png")), "no contact/*.png")
    c.check("scenes", (a / "scenes.json").is_file(), "no scenes.json")
    stills = jsonl(a / "still.jsonl")
    c.check("still stretch", len(stills) >= 1, "no still span found")
    captions = jsonl(a / "captions.jsonl")
    # Only the frames stage 3 uses are captioned: 60 per hour, at least one.
    duration = json.loads((session / "session.json").read_text())["duration_s"]
    picked = min(len(frames), max(1, math.ceil(60 * duration / 3600)))
    c.check(
        "captions per picked frame",
        len(captions) == picked,
        f"{len(captions)} vs {picked}",
    )
    c.check(
        "no frame in the black lead-in",
        all(f["t"] >= 2.0 or f["kind"] == "marker" for f in frames),
        "a scene frame before 2 s",
    )
    c.check(
        "caption tier",
        all(x.get("model") == "fake:omniroute" for x in captions),
        "model",
    )
    c.check(
        "haiku skipped",
        all(any(s.startswith("haiku") for s in x["skipped"]) for x in captions),
        "skipped",
    )


def check_outputs(c: Checker, session: Path, art: Path, expect: int) -> None:
    """The one draft in the scratch target, the todo call, ticks."""
    research = art / "target" / "docs" / "research"
    stamp = re.match(r"\d{8}-\d{6}", session.name)
    name = f"DOCS-research-dummy-game-{stamp.group(0) if stamp else session.name}.md"
    doc = research / "games" / "dummy-game" / name
    text = doc.read_text() if doc.is_file() else ""
    c.check(
        f"draft {name}",
        "_(pending)_" not in text
        and "e2e answer" in text
        and "- **Status:** answered" in text,
        "missing or unfilled",
    )
    c.check(
        "no polish draft",
        not list(research.rglob("*-pl.md")),
        "a -pl file was written",
    )
    state = json.loads((session / "analysis" / "stage3.json").read_text())
    c.check(
        "stage3.json",
        state.get("draft") == str(doc) and "tokens" in state and "cost_usd" in state,
        json.dumps(state),
    )
    todo = (art / "todo.log").read_text() if (art / "todo.log").is_file() else ""
    c.check(
        "todo task",
        "review Dummy Game research draft" in todo and "--new-note" in todo,
        todo[:200],
    )
    ticks = (
        (art / "tick.log").read_text().splitlines()
        if (art / "tick.log").is_file()
        else []
    )
    c.check("ticks", len(ticks) == expect, f"{len(ticks)} ticks")
    llm = (art / "llm.log").read_text().splitlines()
    c.check(
        "one opus call", sum(line.startswith("opus") for line in llm) == 1, "opus calls"
    )
