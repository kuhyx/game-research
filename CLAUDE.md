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
  FAKE_LLM,TODO_CMD,TARGET,SRC,ANALYZE,PORT}`. Never let a test reach the
  real Steam, todo app, cleanup-plate checkout, microphone or speakers.
- Text-free UI (textgate): icons, colours, numbers; accessibility labels live
  on lines containing `semantic` (`final semanticLabel = ...`).
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
