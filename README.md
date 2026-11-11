# game-research

A desktop recorder for design research on reference games. Pick an installed
Steam game, press Start: the game launches through Steam and its monitor is
recorded with game audio. Drop markers while playing (good, bad, confusing,
note) with the buttons or the session-only hotkeys. After Stop an analysis job
cuts scenes, finds still stretches, samples frames, captions them with a
model fallback chain and has one Claude Opus call fill the target project's
research questions template, in English and Polish.

The UI is text-free (icons, capsule images, numbers) and runs as Flutter web
in a Chrome `--app` window; a local Dart wrapper owns ffmpeg, the files, the
hotkeys and the analysis jobs.

## Install and run (Arch + i3 + X11)

```bash
./install.sh                    # deps (pacman), builds, tick sound, icon, .desktop
gtk-launch game-research        # or dmenu: PlayStudy
```

`install.sh --step deps|build|tick|desktop|hooks` runs one step.

## Use

| action | button | hotkey (only while recording) |
|---|---|---|
| start | play | - |
| good / bad / confusing | thumbs up / thumbs down / question mark | Mod+F1 / Mod+F2 / Mod+F3 |
| note | note (one-line field, Enter) | Mod+F4 (dmenu line) |
| stop | stop | Mod+Shift+F4, or quit the game |

Each marker plays a short tick and flashes a 300 ms border on the game's
monitor (green, red, yellow, blue).

Sessions land in `~/data/game-research/<stamp>-<game>/`:
`recording.mkv` (HEVC NVENC near-lossless, FLAC, one chapter per marker),
`markers.jsonl`, `session.json` and `analysis/` (scenes, stills, frames,
clips, contact sheets, captions, status). The drafts go to
`<target>/docs/research/DOCS-research-<game>.md` and its `-pl` twin,
uncommitted, plus one todo task to review them.

## Requirements

ffmpeg with NVENC (falls back to H.264 NVENC, then libx264), PipeWire/Pulse,
sxhkd, dmenu, xrandr, Tk for the flash helper, a Chrome-family browser,
Flutter 3.47.9. Captions: `claude` (subscription), the OmniRoute gateway on
`127.0.0.1:20128` (key read from `~/.config/omniroute/api_key` at run time),
ollama with `qwen3-vl:30b-a3b-instruct`.

## Development

```bash
scripts/test.sh core|desktop|analysis|app   # Dart tests, one dir per call
scripts/test.sh coverage                    # every lib/ line covered
scripts/test.sh py                          # flash helper tests (xvfb-run)
e2e/run.sh build && e2e/run.sh up && e2e/run.sh F1 && e2e/run.sh F1-check
e2e/screenshot.sh <dir>                     # GUI at 2560x1440 and 3840x2160
```

The E2E runs on a private Xvfb with a fake Steam, fake models and a fake todo
CLI; it never touches the real display, speakers or Steam.
