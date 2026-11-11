#!/bin/bash
# E2E flows of game-research (DOCS-features.md). One phase per call, each < 60 s.
#
#   e2e/run.sh build      flutter build web + dart build cli (heavy, capped)
#   e2e/run.sh up         private Xvfb, fixtures, wrapper unit, headless GUI
#   e2e/run.sh F1         session through GUI + hotkeys, stop by hotkey
#   e2e/run.sh F1-check   wait for the analysis job, assert every artefact
#   e2e/run.sh F2         session that stops itself when the game exits
#   e2e/run.sh F4         records the monitor the game window is on (needs
#                         E2E_LAYOUT=dual at `up`: DP-0 + HDMI-0 like kuhy's)
#   e2e/run.sh down       stop units, the dummy game and the browser
#
# Artefacts: ~/data/claude-scratch/e2e/game-research/<run>/ (latest -> newest).

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

build() {
	local capped="${HOME}/.claude/scripts/capped.sh"
	(cd "$E2E_REPO" && CAP_MEM=4G CAP_CPU_PCT=20 "$capped" flutter build web --release --no-web-resources-cdn)
	(cd "$E2E_REPO" && CAP_MEM=4G CAP_CPU_PCT=20 "$capped" dart build cli -t bin/game_research_desktop.dart -o build/cli)
	(cd "$E2E_REPO" && CAP_MEM=4G CAP_CPU_PCT=20 "$capped" dart build cli -t bin/game_research_analyze.dart -o build/analyze)
}

fixtures() {
	local steam="${ART}/steam" target="${ART}/target/docs/research"
	mkdir -p "${steam}/steamapps" "${steam}/appcache/librarycache/${E2E_APPID}" "$target"
	printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"%s"\n\t"StateFlags"\t\t"4"\n}\n' \
		"$E2E_APPID" "$E2E_GAME" >"${steam}/steamapps/appmanifest_${E2E_APPID}.acf"
	ffmpeg -v error -y -f lavfi -i "color=c=0x3c6e9a:s=600x900" -frames:v 1 \
		"${steam}/appcache/librarycache/${E2E_APPID}/library_600x900.jpg"
	cp "${E2E_REPO}/test/fixtures/DOCS-research-questions.md" \
		"${E2E_REPO}/test/fixtures/DOCS-research-questions-pl.md" "$target/"
	git -C "${ART}/target" init -q
}

wrapper_env() {
	local e shim=""
	[[ ! -f "${ART}/monitors" ]] || shim="${E2E_REPO}/e2e/shim:"
	for e in \
		GAME_RESEARCH_TEST=1 "GAME_RESEARCH_PORT=${E2E_PORT}" \
		"GAME_RESEARCH_DATA=${ART}/data" "GAME_RESEARCH_STEAM_ROOT=${ART}/steam" \
		"GAME_RESEARCH_STEAM_CMD=${E2E_REPO}/e2e/fake_steam.sh" \
		"GAME_RESEARCH_STEAM_PID=${ART}/steam.pid" \
		"GAME_RESEARCH_STEAM_ENV=GAME_RESEARCH_E2E_ART=${ART}" \
		"GAME_RESEARCH_DISPLAY=${E2E_DISPLAY}" \
		GAME_RESEARCH_AUDIO=lavfi GAME_RESEARCH_FPS=30 GAME_RESEARCH_STILL_S=4 \
		"GAME_RESEARCH_SRC=${ART}" "GAME_RESEARCH_TARGET=${ART}/target" \
		"GAME_RESEARCH_TICK_CMD=${E2E_REPO}/e2e/fake_tick.sh" \
		"GAME_RESEARCH_FAKE_LLM=${E2E_REPO}/e2e/fake_llm.sh" \
		"GAME_RESEARCH_TODO_CMD=${E2E_REPO}/e2e/fake_todo.sh" \
		"GAME_RESEARCH_E2E_ART=${ART}" "PATH=${shim}${HOME}/.local/bin:/usr/local/bin:/usr/bin" \
		"HOME=${HOME}"; do
		printf -- '--setenv=%s\n' "$e"
	done
}

up() {
	down quiet
	ART="${E2E_ROOT}/$(date +%Y%m%d-%H%M%S)"
	mkdir -p "$ART"
	ln -sfn "$ART" "${E2E_ROOT}/latest"
	step "fixtures in ${ART}"
	fixtures
	[[ ${E2E_LAYOUT:-} != dual ]] || dual_monitors
	step "Xvfb ${E2E_DISPLAY}"
	# A server already on this display would make every check run against
	# something we did not start: refuse it.
	! DISPLAY="$E2E_DISPLAY" xdpyinfo >/dev/null 2>&1 || fail "${E2E_DISPLAY} is already taken"
	local size=1280x720
	[[ ${E2E_LAYOUT:-} != dual ]] || size=6400x2160
	systemd-run --user --collect --quiet --unit gr-e2e-xvfb \
		Xvfb "$E2E_DISPLAY" -screen 0 "${size}x24" -nolisten tcp
	wait_for "DISPLAY=${E2E_DISPLAY} xdpyinfo >/dev/null 2>&1" 10 || fail "Xvfb did not start"
	systemctl --user is-active --quiet gr-e2e-xvfb || fail "gr-e2e-xvfb unit is not active"
	step "wrapper on :${E2E_PORT}"
	local bin="${E2E_REPO}/build/cli/bundle/bin/game_research_desktop"
	[[ -x $bin ]] || fail "no wrapper build; run e2e/run.sh build"
	mapfile -t envs < <(wrapper_env)
	systemd-run --user --collect --quiet --unit gr-e2e-wrapper \
		-p "WorkingDirectory=${E2E_REPO}" "${envs[@]}" "$bin" --serve-only
	wait_for "api /api/state >/dev/null 2>&1" 15 || fail "wrapper did not answer"
	systemctl --user is-active --quiet gr-e2e-wrapper || fail "gr-e2e-wrapper unit is not active"
	step "headless GUI"
	fwd start --url "http://127.0.0.1:${E2E_PORT}/" --profile "${ART}/profile" \
		--cdp-port "$E2E_CDP" --size 2560x1440 >/dev/null
	fwd wait "$E2E_GAME" --timeout 30 >/dev/null || fail "game tile never showed"
	echo "UP ${ART}"
}

# kuhy's two monitors (2026-11-11) on one 6400x2160 Xvfb. Xvfb ignores
# `xrandr --setmonitor`, so e2e/shim/xrandr (first on the wrapper's PATH)
# lists them from this file; the window and the ffmpeg grab stay real.
dual_monitors() {
	printf '%s\n' 'Monitors: 2' \
		' 0: +*DP-0 3840/620x2160/340+0+0  DP-0' \
		' 1: +HDMI-0 2560/698x1440/393+3840+0  HDMI-0' >"${ART}/monitors"
}

down() {
	local u pid
	if [[ -L "${E2E_ROOT}/latest" && -f "$(art_dir)/game.pid" ]]; then
		pid="$(cat "$(art_dir)/game.pid")"
		kill "$pid" 2>/dev/null || true
	fi
	fwd stop >/dev/null 2>&1 || true
	for u in "${E2E_UNITS[@]}"; do
		systemctl --user stop "${u}.service" 2>/dev/null || true
	done
	[[ ${1:-} == quiet ]] || echo "DOWN"
}

main() {
	case "${1:-}" in
	build) build ;;
	up) up ;;
	down) down ;;
	F1) FLOW=F1 ART="$(art_dir)" bash "${E2E_REPO}/e2e/f1_session.sh" ;;
	F1-check) FLOW=F1 ART="$(art_dir)" bash "${E2E_REPO}/e2e/f1_check.sh" ;;
	F2) FLOW=F2 ART="$(art_dir)" bash "${E2E_REPO}/e2e/f2_autostop.sh" ;;
	F4) FLOW=F4 ART="$(art_dir)" bash "${E2E_REPO}/e2e/f4_monitor.sh" ;;
	*) die "usage: e2e/run.sh build|up|F1|F1-check|F2|F4|down" ;;
	esac
}

main "$@"
