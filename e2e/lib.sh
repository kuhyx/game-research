#!/bin/bash
# Sourced library: its globals are used by the scripts that source it.
# shellcheck disable=SC2034
# Shared helpers for the E2E flows (sourced, never run).
#
# Everything runs on a PRIVATE Xvfb (:147 by default) and a private headless
# chromium driven by flutter-web-drive: never kuhy's display :0, never his
# speakers, never his real Steam, todo app or cleanup-plate checkout.
# Long-lived processes are transient `systemd-run --user` units, because a
# child of one Bash call dies with that call's scope.

set -euo pipefail

# Every unit this suite starts (Xvfb, wrapper, chromium, the wrapper's own
# units) goes through bgshim/systemd-run: background CCD, SCHED_IDLE.
PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bgshim:${PATH}"
export PATH

E2E_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly E2E_REPO
readonly E2E_ROOT="${HOME}/data/claude-scratch/e2e/game-research"
readonly E2E_DISPLAY="${E2E_DISPLAY:-:147}"
readonly E2E_PORT="${E2E_PORT:-8806}"
readonly E2E_CDP="${E2E_CDP:-9361}"
readonly E2E_APPID=4242
readonly E2E_GAME="Dummy Game"
readonly E2E_UNITS=(gr-e2e-wrapper gr-e2e-xvfb "playstudy-steam-${E2E_PORT}")
readonly E2E_FWD_APP=game-research-e2e
readonly E2E_BG_CPUS="6-11,18-23"

die() {
	echo "e2e: $*" >&2
	exit 1
}

# One numbered step, logged before it runs, so a failure's step is the last line.
STEP=0
step() {
	STEP=$((STEP + 1))
	echo "step ${STEP}: $*"
}

# Fails the flow with an artefact: a screenshot of the GUI and of the Xvfb.
fail() {
	local art="${ART:-$E2E_ROOT}"
	mkdir -p "$art"
	fwd shot "${art}/fail-gui.png" >/dev/null 2>&1 || true
	DISPLAY="$E2E_DISPLAY" import -window root "${art}/fail-xvfb.png" 2>/dev/null || true
	echo "FAIL ${FLOW:-?} step ${STEP}: $*; shots: ${art}/fail-*.png" >&2
	exit 1
}

# flutter-web-drive CLI on our own app namespace.
fwd() {
	PYTHONPATH="${HOME}/src/utils" python3 -m flutter_web_drive --app "$E2E_FWD_APP" "$@"
}

# The artefact folder of the current run (made by `up`).
art_dir() {
	local latest="${E2E_ROOT}/latest"
	[[ -L $latest ]] || die "no run: start with 'e2e/run.sh up'"
	readlink -f "$latest"
}

# Wall time now, seconds with ms.
now() { date +%s.%3N; }

# Waits up to $1 s until /api/state reports phase $2 (the GUI's stop
# button shows already while the game is starting; recording starts with
# the game window).
wait_phase() {
	wait_for "api /api/state | grep -q '\"phase\":\"$2\"'" "$1"
}

# Appends one fired marker to fired.jsonl: {"tag":..,"wall":..,"via":..}.
fired() {
	printf '{"tag":"%s","wall":%s,"via":"%s"}\n' "$1" "$2" "$3" >>"${ART}/fired.jsonl"
}

# Waits up to $2 s for the command in $1 to succeed.
wait_for() {
	local cmd="$1" limit="$2" i
	for ((i = 0; i < limit * 5; i++)); do
		eval "$cmd" && return 0
		sleep 0.2
	done
	return 1
}

xkey() { DISPLAY="$E2E_DISPLAY" xdotool key --clearmodifiers "$1"; }

api() { curl -fsS -m 5 "http://127.0.0.1:${E2E_PORT}$1"; }
