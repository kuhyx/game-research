#!/bin/bash
# Stands in for `steam` in the E2E: `fake_steam.sh steam://rungameid/<id>`
# runs the dummy game on the private Xvfb the way Steam's reaper would: with
# `AppId=<id>` in its command line. No `SteamAppId` in its environment on
# purpose: steam-backlog-enforcer kills (and notifies kuhy about) any
# process carrying an unapproved SteamAppId; the wrapper matches either.
# The wrapper starts it as the main process of its own Steam unit
# (playstudy-steam-<port>), so it execs the game: the unit lives as long as
# the game. Its lifetime comes from $GAME_RESEARCH_E2E_ART/game_life, its
# window rect (WxH+X+Y, default full screen) from game_geometry; its PID
# goes to game.pid.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
uri="${1:?usage: fake_steam.sh steam://rungameid/<id>}"
appid="${uri##*/}"
life="$(cat "${ART}/game_life" 2>/dev/null || echo 600)"
geometry="$(cat "${ART}/game_geometry" 2>/dev/null || true)"
echo "$uri" >>"${ART}/steam.log"
echo $$ >"${ART}/game.pid"
exec python3 "$(dirname "$0")/dummy_game.py" "AppId=${appid}" \
	--life "$life" --geometry "$geometry" >>"${ART}/game.log" 2>&1 </dev/null
