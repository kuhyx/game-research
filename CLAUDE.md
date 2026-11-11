# game-research

Public repo `kuhyx/game-research`, branch `main`, push directly. No secrets,
keys or personal data in the repo: keys are read from `~/.config/...` at run
time. Commit subjects <= 50 chars.

## Layout

`lib/core/` pure logic (markers, chapters, sampling, captions chain, synthesis
contract, Steam manifests, xrandr, hotkeys, ffmpeg argv) | `lib/desktop/` the
wrapper (config seams, `Sys` process seam, recorder, session controller and
services, HTTP server, launcher) | `lib/analysis/` the job (stages 1-3, tiers,
runner) | `lib/app/` the Flutter UI | `bin/` two entry points |
`helpers/flash_overlay.py` the border flash (Tk) | `e2e/` flows F1, F2 |
`tool/` launcher, .desktop template, coverage check, tier smoke.

## Rules

- Never open windows, move focus, send input or play audio on kuhy's display
  :0. Tests use the `Sys` fakes; the E2E uses `Xvfb :147`, headless chromium
  (flutter-web-drive) and `GAME_RESEARCH_TEST=1`, which refuses display `:0`.
- Every side effect has an env seam (`lib/desktop/config.dart`):
  `GAME_RESEARCH_{DATA,STEAM_ROOT,STEAM_CMD,DISPLAY,OUTPUT,AUDIO,TICK_CMD,
  FAKE_LLM,TODO_CMD,TARGET,SRC,ANALYZE,PORT,LOG,AUTOSTART_S,DEFAULT_APPID,
  WINDOW_TIMEOUT_S,RELAUNCH_S,STEAM_PID,STEAM_ENV,PROC,CAPTURE}`. `ANALYZE=off`
  starts no analysis job. `CAPTURE=auto` records with gpu-screen-recorder
  (GPU capture + encode); it cannot run under Xvfb, so E2E and off-screen
  runs always take the x11grab fallback. Analysis jobs wait while
  `<data>/recording.pid` names a live process.
- steam-backlog-enforcer kills (and notifies kuhy about) any process with
  an unapproved `SteamAppId` in its environment: fakes never set it. Never let a test reach the
  real Steam, todo app, cleanup-plate checkout, microphone or speakers.
- Text-free UI (textgate): icons, colours, numbers; accessibility labels live
  on lines containing `semantic` (`final semanticLabel = ...`).
  One exception (kuhy, 2026-11-11: "put them as text I allow it in this case"): each control's global hotkey as a key legend (`Super+F1`) from `kHotkeys`, `lib/app/shortcut_label.dart`.
- No LLM adjudicates anything: tier skips, stage results and the synthesis
  JSON are checked by code; a missing caption or a malformed draft fails the
  stage (fail closed).
- `dart build cli` builds one entry point per output folder: wrapper in
  `build/cli`, analyzer in `build/analyze`.
- Files stay at 250 lines or fewer (pre-commit `line-cap`).

## Commands (heavy ones through `~/.claude/scripts/capped.sh`)

- `./install.sh [--step deps|build|tick|desktop|hooks]`
- `scripts/test.sh core|desktop|analysis|app|coverage|py`
- `e2e/run.sh build|up|F1|F1-check|F2|down`, `e2e/screenshot.sh <dir>`
- `dart run tool/smoke_tier.dart <haiku|omniroute|ollama> <frame.png>`: one
  real caption call (synthetic frames only for OmniRoute: free providers log
  prompts). ollama needs ~40 s to load the model the first time.
- `pre-commit run --all-files`

### Driving the app (agents)

- Event log: `~/data/game-research/playstudy.jsonl` (`<data>/playstudy.jsonl`),
  one JSON object per step: `app_start`, `picker` (games + state), every
  `api` POST with its status, `autostart_arm/fire`, `cancel`, `steam_client`
  (pid or null), `launch` (argv + exit code), `waiting`, `relaunch`,
  `already_running`, `window`, `record_start/stop`, `error` (step + message).
- Off-screen run, never on :0: start `Xvfb :N` as a `systemd-run --user`
  unit, then `systemd-run --user --collect --unit <name> tool/game_research_app.sh
  --display :N` (the window call blocks). Port 18800+N, data
  `~/data/claude-scratch/playstudy/display-N`, its own Chrome profile, muted
  Chrome/Steam/game (dead audio and D-Bus sockets), silent recording, no
  analysis, Proton on wined3d. Steam is single-instance: check
  `~/.steam/steam.pid` is dead first and `steam -shutdown` (DISPLAY=:N) after.
- Control (same `--display :N` or `--port P`): `playstudy --status`,
  `--games`, `--sessions`, `--session start [--appid N]`, `--session stop`,
  `--autostart [--appid N]`, `--cancel`, `--marker good|bad|confusing|note`,
  `--log [N]`, `--wait idle|armed|launching|waiting|recording [--timeout S]`.
  JSON out; exit 0 ok, 1 refused/timeout, 2 usage, 3 no wrapper.
- HTTP: `GET /api/state|games|sessions`, `POST /api/start[?appid]`,
  `/api/stop`, `/api/autostart[?appid]`, `/api/autostart/cancel`,
  `/api/marker?tag=`. GUI semantics labels: `start`/`stop`, `autostart`,
  `waiting for game`, `marker <tag>`, `note text`, game tiles by name
  (`<name>, updating` while Steam has not finished).
