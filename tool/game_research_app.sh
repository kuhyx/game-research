#!/bin/bash
# ============================================================================
# game-research launcher (the .desktop entry's Exec).
#
# 1. builds the web page and both binaries if missing,
# 2. starts the wrapper on 127.0.0.1:8805 as a `systemd-run --user` unit
#    unless something already answers (it then outlives this script and the
#    window, so a running session and its analysis job are never cut off),
# 3. opens the Chrome app window through the wrapper's --window-only mode,
#    so the browser flags live in exactly one place (lib/desktop/browser.dart).
#
# Usage: game_research_app.sh [--rebuild]
# ============================================================================

set -euo pipefail

APP_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
readonly APP_DIR
readonly PORT="${GAME_RESEARCH_PORT:-8805}"
readonly WEB_INDEX="${APP_DIR}/build/web/index.html"
readonly WRAPPER="${APP_DIR}/build/cli/bundle/bin/game_research_desktop"
readonly ANALYZER="${APP_DIR}/build/analyze/bundle/bin/game_research_analyze"
readonly UNIT="game-research-wrapper"

REBUILD=0

die() {
	echo "game_research_app: $*" >&2
	exit 1
}

wrapper_up() {
	curl -fsS -o /dev/null --max-time 1 "http://127.0.0.1:${PORT}/api/state" 2>/dev/null
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
	local envs
	systemctl --user stop "${UNIT}.service" 2>/dev/null || true
	mapfile -t envs < <(unit_env)
	systemd-run --user --collect --quiet --unit "$UNIT" \
		-p "WorkingDirectory=${APP_DIR}" "${envs[@]}" \
		"$WRAPPER" --serve-only
	local _
	for _ in $(seq 50); do
		wrapper_up && return 0
		sleep 0.1
	done
	die "wrapper did not answer on :${PORT}; see journalctl --user -u ${UNIT}"
}

main() {
	if ((REBUILD)) || [[ ! -f $WEB_INDEX || ! -x $WRAPPER || ! -x $ANALYZER ]]; then
		build
	fi
	wrapper_up || start_wrapper
	cd "$APP_DIR"
	exec "$WRAPPER" --window-only
}

case "${1:-}" in
--rebuild) REBUILD=1 ;;
"") ;;
*)
	echo "usage: game_research_app.sh [--rebuild]" >&2
	exit 2
	;;
esac
main
