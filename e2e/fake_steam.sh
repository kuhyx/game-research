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
#
# `fake_steam.sh steam://install/<id>` (the research-game add) stages an
# install instead: it writes steam/steamapps/appmanifest_<id>.acf under the
# art dir, downloading (StateFlags 1026, the tile's ring) for install_s
# seconds (default 20), then installed (StateFlags 4). Name: install_name.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
uri="${1:?usage: fake_steam.sh steam://rungameid/<id>}"
appid="${uri##*/}"
readonly TOTAL=1000000000

# One manifest, written whole (tmp + mv) so the wrapper never reads half.
write_acf() {
	local file="$1" flags="$2" done="$3" name="$4"
	printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"%s"\n\t"installdir"\t\t"%s"\n\t"BytesToDownload"\t\t"%s"\n\t"BytesDownloaded"\t\t"%s"\n}\n' \
		"$appid" "$name" "$flags" "$name" "$TOTAL" "$done" >"${file}.tmp"
	mv "${file}.tmp" "$file"
}

install() {
	local apps="${ART}/steam/steamapps" secs name step ms
	secs="$(cat "${ART}/install_s" 2>/dev/null || echo 20)"
	name="$(cat "${ART}/install_name" 2>/dev/null || echo "App ${appid}")"
	mkdir -p "$apps"
	ms=$((secs * 100)) # each of the ten steps, whole seconds in install_s
	for ((step = 1; step < 10; step++)); do
		write_acf "${apps}/appmanifest_${appid}.acf" 1026 $((TOTAL * step / 10)) "$name"
		sleep "$((ms / 1000)).$(printf '%03d' $((ms % 1000)))"
	done
	write_acf "${apps}/appmanifest_${appid}.acf" 4 "$TOTAL" "$name"
}

if [[ $uri == steam://install/* ]]; then
	echo "$uri" >>"${ART}/steam.log"
	install
	exit 0
fi

life="$(cat "${ART}/game_life" 2>/dev/null || echo 600)"
geometry="$(cat "${ART}/game_geometry" 2>/dev/null || true)"
echo "$uri" >>"${ART}/steam.log"
echo $$ >"${ART}/game.pid"
exec python3 "$(dirname "$0")/dummy_game.py" "AppId=${appid}" \
	--life "$life" --geometry "$geometry" >>"${ART}/game.log" 2>&1 </dev/null
