#!/bin/bash
# ============================================================================
# game-research launcher (`playstudy`, the .desktop entry's Exec).
#
# 1. builds the web page and both binaries if missing,
# 2. starts the wrapper on 127.0.0.1:<port> as a `systemd-run --user` unit
#    unless something already answers (it then outlives this script and the
#    window, so a running session and its analysis job are never cut off);
#    an idle wrapper older than its binary (after an install) is restarted,
# 3. opens the Chrome app window through the wrapper's --window-only mode,
#    so the browser flags live in exactly one place (lib/desktop/browser.dart).
#    The window arms the 3 s autostart ring (last game, default Librarian).
#
# Usage:
#   playstudy [--rebuild] [--no-autostart] [--display :N] [--port P] [--no-window]
#   playstudy [--display :N] [--port P] --status | --games | --sessions
#             | --session start [--appid N] | --session stop | --autostart
#             | --cancel | --marker TAG | --log [N] | --wait PHASE [--timeout S]
#
# --display :N (never :0) is the off-screen mode for agents: wrapper, Chrome,
# Steam, recording and hotkeys all live on that X display; the port defaults
# to 18800+N, the data dir to ~/data/claude-scratch/playstudy/display-N, the
# Chrome profile is per port, the tick is silent, Chrome, Steam and the game
# are muted, the recording's audio is silence and no analysis job runs. kuhy's
# own instance (port 8805, unit game-research-wrapper) is never touched.
# ============================================================================

set -euo pipefail

APP_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
readonly APP_DIR
readonly WEB_INDEX="${APP_DIR}/build/web/index.html"
readonly WRAPPER="${APP_DIR}/build/cli/bundle/bin/game_research_desktop"
readonly ANALYZER="${APP_DIR}/build/analyze/bundle/bin/game_research_analyze"

REBUILD=0
WINDOW=1
OFFSCREEN=""
PORT="${GAME_RESEARCH_PORT:-8805}"
WINDOW_ARGS=()
CONTROL=()
COMMAND=0

die() {
	echo "game_research_app: $*" >&2
	exit 1
}

usage() {
	sed -n '/^# Usage:/,/^# --display/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

wrapper_up() {
	curl -fsS -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/api/state" 2>/dev/null
}

# The wrapper outlives every window, so after an install it would keep
# serving old code to the new page. Stale = its binary is newer than the
# running unit and nothing records or is pending: then it is restarted.
stale_wrapper() {
	local since state
	since="$(systemctl --user show -p ActiveEnterTimestamp --value "$(unit_name).service" 2>/dev/null)"
	[[ -n $since ]] || return 1
	(($(stat -c %Y "$WRAPPER") > $(date -d "$since" +%s))) || return 1
	state="$(curl -fsS --max-time 1 "http://127.0.0.1:${PORT}/api/state" 2>/dev/null)" || return 1
	[[ $state == *'"recording":false'* && ! $state =~ \"phase\":\"(armed|launching|waiting)\" ]]
}

# kuhy's instance keeps its historical unit name; every other port its own.
unit_name() {
	if [[ $PORT == 8805 ]]; then echo game-research-wrapper; else echo "game-research-wrapper-${PORT}"; fi
}

build() {
	(cd "$APP_DIR" && flutter build web --release --no-web-resources-cdn)
	(cd "$APP_DIR" && dart build cli -t bin/game_research_desktop.dart -o build/cli)
	(cd "$APP_DIR" && dart build cli -t bin/game_research_analyze.dart -o build/analyze)
}

# --setenv flags for the wrapper unit: the user manager's PATH lacks
# ~/.local/bin (dart, claude); X needs DISPLAY (and XAUTHORITY when set);
# every GAME_RESEARCH_* override (port included) must reach the wrapper.
unit_env() {
	local name
	printf -- '--setenv=%s\n' "PATH=${HOME}/.local/bin:/usr/local/bin:/usr/bin" \
		"HOME=${HOME}" "DISPLAY=${DISPLAY:-:0}"
	[[ -n ${XAUTHORITY:-} ]] && printf -- '--setenv=XAUTHORITY=%s\n' "$XAUTHORITY"
	while IFS= read -r name; do
		printf -- '--setenv=%s=%s\n' "$name" "${!name}"
	done < <(compgen -e | grep '^GAME_RESEARCH_' || true)
}

start_wrapper() {
	local envs unit
	unit="$(unit_name)"
	systemctl --user stop "${unit}.service" 2>/dev/null || true
	mapfile -t envs < <(unit_env)
	systemd-run --user --collect --quiet --unit "$unit" \
		-p "WorkingDirectory=${APP_DIR}" "${envs[@]}" \
		"$WRAPPER" --serve-only
	local _
	for _ in $(seq 50); do
		wrapper_up && return 0
		sleep 0.1
	done
	die "wrapper did not answer on :${PORT}; see journalctl --user -u ${unit}"
}

# Off-screen mode: everything on display $1, nothing on kuhy's screen,
# speakers or data. Explicit GAME_RESEARCH_* values still win.
offscreen() {
	local display="$1" n="${1#:}"
	[[ $display =~ ^:[0-9]+$ && $n != 0 ]] || die "--display needs :N with N != 0"
	DISPLAY="$display" xdpyinfo >/dev/null 2>&1 || die "no X server on ${display}"
	export DISPLAY="$display" GAME_RESEARCH_DISPLAY="$display"
	[[ -n ${GAME_RESEARCH_PORT:-} ]] || PORT=$((18800 + n))
	export GAME_RESEARCH_PORT="$PORT"
	: "${GAME_RESEARCH_DATA:=${HOME}/data/claude-scratch/playstudy/display-${n}}"
	: "${GAME_RESEARCH_TICK_CMD:=true}"
	: "${GAME_RESEARCH_AUDIO:=lavfi}"
	# No analysis job: it would call real models and write drafts and a
	# todo task for kuhy's target repo from a test session.
	: "${GAME_RESEARCH_ANALYZE:=off}"
	# Steam and the game get no audio server and no session bus (its tray
	# icon, notifications and portals would reach kuhy's desktop): both point
	# at a plain file. It must exist, since Steam's runtime (bwrap)
	# bind-mounts those paths, but nothing can connect to it. Proton draws
	# through wined3d (OpenGL): Xvfb offers no Vulkan presentation.
	local dead="${XDG_RUNTIME_DIR:-/tmp}/playstudy-nosock"
	: >"$dead"
	: "${GAME_RESEARCH_STEAM_ENV:=PULSE_SERVER=unix:${dead} PIPEWIRE_REMOTE=${dead} SDL_AUDIODRIVER=dummy PROTON_USE_WINED3D=1 DBUS_SESSION_BUS_ADDRESS=unix:path=${dead}}"
	export GAME_RESEARCH_DATA GAME_RESEARCH_TICK_CMD \
		GAME_RESEARCH_AUDIO GAME_RESEARCH_STEAM_ENV GAME_RESEARCH_ANALYZE
	unset XAUTHORITY
}

main() {
	[[ -z $OFFSCREEN ]] || offscreen "$OFFSCREEN"
	if ((${#CONTROL[@]})); then
		((COMMAND)) || usage
		[[ -x $WRAPPER ]] || die "no wrapper build; run with --rebuild"
		# A control command never opens a window, even from an old build
		# that would not know the flag and fall through to the window path.
		GAME_RESEARCH_BROWSER=/usr/bin/false exec "$WRAPPER" "${CONTROL[@]}"
	fi
	if ((REBUILD)) || [[ ! -f $WEB_INDEX || ! -x $WRAPPER || ! -x $ANALYZER ]]; then
		build
	fi
	if ! wrapper_up || stale_wrapper; then start_wrapper; fi
	((WINDOW)) || exit 0
	cd "$APP_DIR"
	exec "$WRAPPER" --window-only "${WINDOW_ARGS[@]}"
}

while (($#)); do
	case "$1" in
	--rebuild) REBUILD=1 ;;
	--no-window) WINDOW=0 ;;
	--no-autostart) WINDOW_ARGS+=(--no-autostart) ;;
	--display) OFFSCREEN="${2:?--display needs :N}" && shift ;;
	--port) PORT="${2:?--port needs a number}" && export GAME_RESEARCH_PORT="$PORT" && shift ;;
	--status | --games | --sessions | --autostart | --cancel) CONTROL+=("$1") && COMMAND=1 ;;
	--session | --marker | --wait) CONTROL+=("$1" "${2:?$1 needs a value}") && COMMAND=1 && shift ;;
	--appid | --timeout) CONTROL+=("$1" "${2:?$1 needs a value}") && shift ;;
	--log)
		CONTROL+=(--log) && COMMAND=1
		[[ ${2:-} =~ ^[0-9]+$ ]] && CONTROL+=("$2") && shift
		;;
	-h | --help) usage ;;
	*) usage ;;
	esac
	shift
done
main
