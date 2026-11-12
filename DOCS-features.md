# FEATURES: game-research

> Feature map + core-flow ground truth (skill: `e2e-ground-truth`). A
> user-visible change updates its row in the same commit.

- **Primary target:** desktop (Flutter web in a Chrome `--app` window on
  HDMI-0, wrapper on `127.0.0.1:8805`)
- **Driver:** flutter-web-drive (headless chromium) + private `Xvfb :147`
  (xdotool hotkeys, dmenu, flash, x11grab) + fake Steam / models / todo
- **Run one flow:** `e2e/run.sh build`, `e2e/run.sh up`, then `e2e/run.sh F1`,
  `e2e/run.sh F1-check`, `e2e/run.sh F2`, `E2E_LAYOUT=dual e2e/run.sh up` + `e2e/run.sh F4`, `e2e/run.sh down`
- **Artefacts:** `~/data/claude-scratch/e2e/game-research/<run>/`

## Feature map

| feature | how to reach it | expected outcome |
|---|---|---|
| Game picker | window opens -> capsule grid (`/api/games`) | one tile per Steam game with a manifest (tools skipped); art: Steam's librarycache (flat, `<id>/` or hashed `<id>/<hash>/library_600x900*` or `library_capsule.jpg`), else downloaded from the Steam CDN (`library_600x900.jpg`, then `header.jpg`) into `<data>/art/<id>.jpg`, a miss remembered 1 day (`GAME_RESEARCH_ART=off` and test mode never go online), else a procedural hue tile; a half-downloaded game shows a download glyph and its progress bar; no games = red empty glyph; no text |
| Autostart | open PlayStudy (launcher adds `?autostart=1`) | a 3 s ring drains around the stop button, then the last game (default Librarian 4197610) starts; Esc or the button cancels |
| Start | pick capsule -> play button (`start`), or autostart | Steam client down: `systemd-run --user --unit playstudy-steam-<port> steam steam://rungameid/<id>`; up: `steam <uri>` handoff (again every 30 s while Steam runs but the game does not); spinner ring while waiting; recording starts when a game-sized window appears (Proton class `steam_app_<id>`); failures show the error glyph and an `error` log line |
| Event log + CLI | `<data>/playstudy.jsonl`; `playstudy --status` etc. | every step logged; control commands in CLAUDE.md |
| Markers by button | thumbs up / thumbs down / question / note buttons | line in `markers.jsonl` (wall, offset_s, tag, note); counter +1; 300 ms border flash in the tag colour on the game output; tick sound; the note line opens for every tag |
| Note by button | any marker button -> one-line field -> Enter (Esc = empty note) | marker stamped at the button press, note text added on Enter; pressing another marker closes an open field empty |
| Hotkeys | Mod+F1 good, Mod+F2 bad, Mod+F3 confusing, Mod+F4 note, Mod+Shift+F4 stop | same as the buttons, each shown as a key legend beside its button (`Super+F1`, from `kHotkeys`); every marker key asks for a note line through dmenu (`ask=1`), stamped at the key press, Esc keeps it empty; keys exist only while a session records (sxhkd unit `game-research-keys-<port>`) |
| Auto stop | quit the game | session ends when no process carries `AppId=<id>` any more (after it was seen once); `ended_by: game-exit` |
| Recording | any session | `~/data/game-research/<stamp>-<game>/recording.mkv`: x11grab of the monitor the game window is on (`xrandr --listmonitors` x window rect, else the primary; `record_start` logs `output` + `output_why`), default-sink monitor audio (never a mic), HEVC NVENC cq 14, one chapter per marker; gpu-screen-recorder path: `-q very_high`, audio `-ac opus` |
| Analysis job | starts after Stop (`systemd-run --user`) | `analysis/status.json` drives the ring (`state` running / waiting / interrupted / done / failed, `tokens`, `cost_usd`, `eta_s`, `started_unix`); stages resume from their own outputs; one job at a time machine-wide (`<data>/analysis.lock`: pid + start time), a second one is `waiting` and starts when the first ends |
| Resume | `game-research-resume.timer` (`install.sh --step resume`), 2 min after boot then every 15 min | `game_research_analyze --resume-all` relaunches interrupted jobs, waiting ones whose retry time passed and sessions never analysed, one at a time, never while `<data>/recording.pid` is live; `failed` is never retried; also deletes `recording.mkv` 14 days after the game's `finish.json` |
| Finish | `game_research_analyze --finish <slug>` | one Opus call merges every session draft (v1 sessions with only `draft_en` too, one per file path) into `games/<slug>/DOCS-research-<slug>.md` and `-report.md`, same 250-line rule; `<data>/games/<slug>/finish.json` + `status.json`; todo task "MANUAL WORK REQUIRED: review <game> research report" |
| Stage 1 | automatic | `scenes.json`, `still.jsonl` (no motion >= 20 s), `frames/` (every marker + scene cuts at most one per 10 s, <= 1280 px), `clips/` (10 s per marker, stream copy, up to +1 s at the start keyframe), `contact/sheet_*.png` |
| Stage 2 | automatic | `captions.jsonl`: one line per frame stage 3 will use (60 per hour, marker frames first; none in the first 2 s unless a marker is there), 8 frames per call with one JSON object per frame checked by code (a malformed batch falls back to single frames), `tier`, `model`, `skipped`, `usage` (a call's tokens sit on its first row); chain haiku -> OmniRoute `agnes/agnes-2.5-flash` -> ollama `qwen3-vl:30b-a3b-instruct`; a frame no tier captions fails the stage (rerun resumes) |
| Stage 3 | automatic | one Opus call; `<target>/docs/research/games/<game>/DOCS-research-<game>-<stamp>.md` (one per session, English, never overwritten; the prompt carries the earlier drafts, every question has a `- **Status:** answered|partial|open` line) written uncommitted without the template's `Why we ask:` lines, blank runs collapsed, at most 250 lines (over: one follow-up Opus call asks for <= 240, a second overflow fails the stage); `stage3.json` has `draft`, `tokens`, `cost_usd`; todo task "MANUAL WORK REQUIRED: review <game> research draft" (`--new-note`); frames shown: ceil(60 x hours), at least 1, marker frames first |
| Game fps | MangoHud (`install.sh --step fps`: layer on for the desktop session, no HUD, `<data>/mangohud.conf`; plus a Steam launch option for the researched game, written to `localconfig.vdf` only while Steam is down) | CSVs land in `<data>/fps-spool/`; at stop the overlapping ones move to `<session>/fps/` and `session.json` gets `fps: {avg, p1_low, min, samples}` (null without a log); events `fps_launch_option`, `fps`; spool pruned after 7 days |
| Target picker | folder chips under the controls | any `~/src/*` with `docs/research/DOCS-research-questions.md`, default cleanup-plate; kept in `~/data/game-research/settings.json` |
| Past sessions | right column | capsule, start `MM-DD HH:MM`, length, marker counts, progress ring (accent running, green done, red failed, amber hourglass waiting for a usage limit, amber pause interrupted), and numbers with an icon: token total, cost, stage, items done/total, minutes left, average game fps; fields missing in old sessions are simply not shown |
| Rerun analysis | refresh button on a row | new job; resumes a failed or unfinished one; on a finished one runs all three stages again (`--force`: new Opus call, drafts overwritten) |
| Draft panel | page button on a row (enabled once the draft exists) | an in-app panel over the window: the draft rendered as markdown, an edit toggle (plain text) and save (`PUT /api/doc`); only `<target>/docs/research/**.md` is readable or writable (403 elsewhere, `..` and symlinks resolved); nothing is spawned; row buttons ignore taps for 5 s after the launcher opened the page or a game / Steam window opened or closed (the stray-click fix for `open-draft` firing alone) |
| Finished control | flag on a game tile (needs a session draft) | `POST /api/games/<id>/finish` runs `game_research_analyze --finish <slug>` (systemd-run like a session job); ring and numbers from `<data>/games/<slug>/status.json`; done: the flag turns into a check and opens the report in the panel (its refresh button reruns) |

## Core flows (3-5)

| id | goal | command | last green |
|---|---|---|---|
| F1 | GUI start, 4 hotkey + 4 button markers, stop by Mod+Shift+F4, full analysis with stub models | `e2e/run.sh F1 && e2e/run.sh F1-check` | 2026-11-11 (68 checks) |
| F2 | session stops by itself when the game exits | `e2e/run.sh F2` | 2026-11-11 |
| F3 | real Steam + Librarian off-screen: open, ring, Steam starts, game window, recording, CLI markers, game exit stops it | manual, CLAUDE.md "Driving the app" | 2026-11-11 (Xvfb :148) |
| F4 | the recording grabs the monitor the game window is on (DP-0 + HDMI-0 layout, game on HDMI-0 -> 2560x1440 video) | `E2E_LAYOUT=dual e2e/run.sh up`, `e2e/run.sh F4` | 2026-11-11 (Xvfb :147, monitors listed by `e2e/shim/xrandr`) |

F1-check asserts: 8 chapters at the marker offsets, each marker offset within
0.5 s of the moment the input was sent, the border flash visible in the
recording at each offset, frames / clips / contact sheet / stills, captions
from the second tier with haiku skipped, one captioned frame per frame stage 3 uses, the single draft filled with status lines (no `-pl`), the todo call and
8 ticks. On failure every flow prints `FAIL F<n> step <i>: <why>; shots:
<path>` and exits non-zero.
