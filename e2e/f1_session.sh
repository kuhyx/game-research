#!/bin/bash
# F1: pick the game, Start through the GUI, fire all four markers by hotkey
# (xdotool on the PRIVATE Xvfb only) and by button, stop with Mod+Shift+F4.
# Every fired marker is logged to fired.jsonl with the wall time before and
# after the input, which f1_check.sh compares against markers.jsonl.

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"
echo 600 >"${ART}/game_life"
: >"${ART}/fired.jsonl"

hotkey() {
	local tag="$1" chord="$2" before
	before="$(now)"
	xkey "$chord"
	fired "$tag" "$before,\"after\":$(now)" key
	sleep 1.2
}

button() {
	local tag="$1" before
	before="$(now)"
	fwd tap "marker ${tag}" --contains >/dev/null || fail "no marker ${tag} button"
	fired "$tag" "$before,\"after\":$(now)" button
}

step "pick ${E2E_GAME}"
fwd tap "$E2E_GAME" >/dev/null || fail "game tile not tappable"
step "start"
fwd tap start >/dev/null || fail "no start button"
wait_phase 20 recording || fail "never reached recording"
step "dummy game running"
wait_for "[[ -s ${ART}/game.pid ]] && kill -0 \$(cat ${ART}/game.pid)" 15 ||
	fail "fake steam never started the game"
sleep 1.5
step "hotkeys good, bad, confusing"
hotkey good super+F1
hotkey bad super+F2
hotkey confusing super+F3
step "hotkey note opens dmenu"
before="$(now)"
xkey super+F4
wait_for "DISPLAY=${E2E_DISPLAY} xdotool search --class dmenu >/dev/null 2>&1" 5 ||
	fail "dmenu never opened"
fired note "$before,\"after\":$(now)" key
DISPLAY="$E2E_DISPLAY" xdotool type --delay 20 'hotkey note'
xkey Return
sleep 1.2
step "buttons good, bad, confusing"
button good
sleep 1
button bad
sleep 1
button confusing
sleep 1
step "button note + text"
button note
fwd wait "note text" --timeout 5 >/dev/null || fail "note field never opened"
fwd tap "note text" >/dev/null
fwd text 'button note' >/dev/null
fwd key Enter >/dev/null
sleep 1
step "idle 8 s for the still detector"
sleep 8
step "stop by Mod+Shift+F4"
xkey super+shift+F4
fwd wait start --timeout 20 >/dev/null || fail "GUI never left recording"
fwd shot "${ART}/after-stop.png" >/dev/null
step "quit the dummy game"
kill "$(cat "${ART}/game.pid")" 2>/dev/null || true
echo "PASS F1 drive (8 markers fired); next: e2e/run.sh F1-check"
