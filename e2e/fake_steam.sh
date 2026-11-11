#!/bin/bash
# Stands in for `steam` in the E2E: `fake_steam.sh steam://rungameid/<id>`
# starts the dummy game on the private Xvfb, the way Steam's reaper would:
# with `AppId=<id>` in its command line. Its lifetime comes from
# $GAME_RESEARCH_E2E_ART/game_life; its PID goes to game.pid.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
uri="${1:?usage: fake_steam.sh steam://rungameid/<id>}"
appid="${uri##*/}"
life="$(cat "${ART}/game_life" 2>/dev/null || echo 600)"
echo "$uri" >>"${ART}/steam.log"
setsid python3 "$(dirname "$0")/dummy_game.py" "AppId=${appid}" --life "$life" \
	>>"${ART}/game.log" 2>&1 </dev/null &
echo $! >"${ART}/game.pid"
