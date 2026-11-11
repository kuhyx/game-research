#!/bin/bash
# F2: a session ends by itself when the game's process (AppId=<id> in its
# cmdline) exits: no Stop button, no hotkey.

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"
echo 5 >"${ART}/game_life"
if [[ -s "${ART}/game.pid" ]]; then kill "$(cat "${ART}/game.pid")" 2>/dev/null || true; fi
rm -f "${ART}/game.pid"

step "pick ${E2E_GAME} and start"
fwd tap "$E2E_GAME" >/dev/null || fail "game tile not tappable"
fwd tap start >/dev/null || fail "no start button"
fwd wait stop --timeout 15 >/dev/null || fail "never reached recording"
step "game exits after 5 s, session stops itself"
fwd wait start --timeout 25 >/dev/null || fail "session did not stop on game exit"
session="$(find "${ART}/data" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
step "session.json says game-exit"
grep -q '"ended_by": *"game-exit"' "${session}/session.json" ||
	fail "ended_by is not game-exit in ${session}/session.json"
[[ -s "${session}/recording.mkv" ]] || fail "no recording.mkv"
echo "PASS F2 ${session}"
