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
| Game picker | window opens -> capsule grid (`/api/games`) | one tile per Steam game with a manifest (tools skipped), cached capsule or a procedural hue tile; a half-downloaded game shows a download glyph and its progress bar; no games = red empty glyph; no text |
| Autostart | open PlayStudy (launcher adds `?autostart=1`) | a 3 s ring drains around the stop button, then the last game (default Librarian 4197610) starts; Esc or the button cancels |
| Start | pick capsule -> play button (`start`), or autostart | Steam client down: `systemd-run --user --unit playstudy-steam-<port> steam steam://rungameid/<id>`; up: `steam <uri>` handoff (again every 30 s while Steam runs but the game does not); spinner ring while waiting; recording starts when a game-sized window appears (Proton class `steam_app_<id>`); failures show the error glyph and an `error` log line |
| Event log + CLI | `<data>/playstudy.jsonl`; `playstudy --status` etc. | every step logged; control commands in CLAUDE.md |
| Markers by button | thumbs up / thumbs down / question / note buttons | line in `markers.jsonl` (wall, offset_s, tag, note); counter +1; 300 ms border flash in the tag colour on the game output; tick sound |
| Note by button | note button -> one-line field -> Enter (Esc = empty) | marker stamped at the button press, note text added on Enter |
| Hotkeys | Mod+F1 good, Mod+F2 bad, Mod+F3 confusing, Mod+F4 note (dmenu line), Mod+Shift+F4 stop | same as the buttons, each shown as a key legend beside its button (`Super+F1`, from `kHotkeys`); keys exist only while a session records (sxhkd unit `game-research-keys-<port>`) |
| Auto stop | quit the game | session ends when no process carries `AppId=<id>` any more (after it was seen once); `ended_by: game-exit` |
| Recording | any session | `~/data/game-research/<stamp>-<game>/recording.mkv`: x11grab of the monitor the game window is on (`xrandr --listmonitors` x window rect, else the primary; `record_start` logs `output` + `output_why`), default-sink monitor audio (never a mic), HEVC NVENC cq 14, FLAC, one chapter per marker |
| Analysis job | starts after Stop (`systemd-run --user`) | `analysis/status.json` drives the ring; stages resume from their own outputs |
| Stage 1 | automatic | `scenes.json`, `still.jsonl` (no motion >= 20 s), `frames/` (every marker + scene cuts at most one per 10 s, <= 1280 px), `clips/` (10 s per marker, stream copy, up to +1 s at the start keyframe), `contact/sheet_*.png` |
| Stage 2 | automatic | `captions.jsonl`: one line per frame with `tier`, `model`, `skipped`; chain haiku -> OmniRoute `agnes/agnes-2.5-flash` -> ollama `qwen3-vl:30b-a3b-instruct`; a frame no tier captions fails the stage (rerun resumes) |
| Stage 3 | automatic | one Opus call; `<target>/docs/research/DOCS-research-<game>.md` + `-pl.md` written uncommitted; todo task "MANUAL WORK REQUIRED: review <game> research draft" (`--new-note`); frames shown: ceil(60 x hours), at least 1, marker frames first |
| Game fps | MangoHud (`install.sh --step fps`: layer on for the desktop session, no HUD, `<data>/mangohud.conf`; plus a Steam launch option for the researched game, written to `localconfig.vdf` only while Steam is down) | CSVs land in `<data>/fps-spool/`; at stop the overlapping ones move to `<session>/fps/` and `session.json` gets `fps: {avg, p1_low, min, samples}` (null without a log); events `fps_launch_option`, `fps`; spool pruned after 7 days |
| Target picker | folder chips under the controls | any `~/src/*` with `docs/research/DOCS-research-questions.md`, default cleanup-plate; kept in `~/data/game-research/settings.json` |
| Past sessions | right column | capsule, start `MM-DD HH:MM`, length, marker counts, progress ring (accent running, green done, red failed) |
| Rerun analysis | refresh button on a row | new job; resumes a failed or unfinished one; on a finished one runs all three stages again (`--force`: new Opus call, drafts overwritten) |
| Open draft | page button on a row (enabled once the draft exists) | `xdg-open` of the English draft |

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
from the second tier with haiku skipped, both drafts filled, the todo call and
8 ticks. On failure every flow prints `FAIL F<n> step <i>: <why>; shots:
<path>` and exits non-zero.
