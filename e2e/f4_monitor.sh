#!/bin/bash
# F4: the recording grabs the monitor the game window is on. 2026-11-11 live
# bug: a remembered output name (DP-2) did not exist on kuhy's :0 and every
# session died at 00:00. Needs `E2E_LAYOUT=dual e2e/run.sh up` (DP-0
# 3840x2160 primary + HDMI-0 2560x1440 at +3840+0); the game opens on HDMI-0.

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"

grep -qs ' HDMI-0$' "${ART}/monitors" ||
	fail "no HDMI-0 monitor: start with E2E_LAYOUT=dual e2e/run.sh up"
if [[ -s "${ART}/game.pid" ]]; then kill "$(cat "${ART}/game.pid")" 2>/dev/null || true; fi
rm -f "${ART}/game.pid"
echo 1600x900+4000+200 >"${ART}/game_geometry"
echo 60 >"${ART}/game_life"

step "start ${E2E_GAME} over HTTP"
curl -fsS -m 5 -X POST "http://127.0.0.1:${E2E_PORT}/api/start?appid=${E2E_APPID}" >/dev/null ||
	fail "POST /api/start refused"
wait_phase 30 recording || fail "never reached recording: $(api /api/state)"
step "record_start names HDMI-0, picked by the window"
start="$(grep '"event":"record_start"' "${ART}/data/playstudy.jsonl" | tail -1)"
grep -q '"output":"HDMI-0"' <<<"$start" || fail "wrong output: ${start}"
grep -q '"output_why":"window"' <<<"$start" || fail "not picked by window: ${start}"
grep -q '"geometry":"2560x1440+3840+0"' <<<"$start" || fail "wrong rect: ${start}"
sleep 2
step "stop; the video is HDMI-0 sized"
curl -fsS -m 5 -X POST "http://127.0.0.1:${E2E_PORT}/api/stop" >/dev/null || fail "stop refused"
wait_phase 30 idle || fail "never back to idle"
session="$(find "${ART}/data" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
size="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
	-of csv=p=0:s=x "${session}/recording.mkv")"
[[ $size == 2560x1440 ]] || fail "recording is ${size}, not 2560x1440"
kill "$(cat "${ART}/game.pid")" 2>/dev/null || true
rm -f "${ART}/game_geometry"
echo "PASS F4 ${session} ${size}"
