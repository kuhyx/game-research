#!/bin/bash
# ============================================================================
# Deploys game-research to this PC: fast-forwards the live checkout (the one
# the .desktop launcher and ~/.local/bin/playstudy point at) to origin/main,
# rebuilds it (install.sh build), refreshes launcher, tick, resume timer and
# the MangoHud config (games only: removes the old session-wide layer),
# then health-checks the NEW wrapper binary off-screen.
#
#   scripts/deploy.sh            pull + install + health check
#   scripts/deploy.sh --check    health check only
#
# Idempotent. Exits non-zero unless the health check passes. Never starts the
# app window and never restarts a running wrapper (it may be recording): a
# running one keeps its old binary but serves build/web from disk, so the new
# UI shows on its next reload; the new wrapper binary on its next start.
#
# Health check: the built wrapper runs --serve-only as a transient user unit
# in test mode (refuses display :0, no analysis, scratch data dir and port),
# and must answer /api/state, serve the page and the design_system logo.
# Needs: git, curl, systemd-run.
# ============================================================================

set -euo pipefail

readonly LIVE="${GAME_RESEARCH_LIVE:-${HOME}/src/game-research}"
readonly CHECK_PORT="${GAME_RESEARCH_CHECK_PORT:-18899}"
readonly UNIT="game-research-deploy-check"
readonly LOGO="assets/packages/design_system/assets/logo/kuhy.svg"

die() {
	echo "deploy.sh: $*" >&2
	exit 1
}

pull() {
	git -C "$LIVE" fetch -q origin main
	git -C "$LIVE" pull -q --ff-only origin main ||
		die "cannot fast-forward ${LIVE} (local changes in the way?)"
	[[ $(git -C "$LIVE" rev-parse HEAD) == "$(git -C "$LIVE" rev-parse origin/main)" ]] ||
		die "${LIVE} is not at origin/main"
}

install_live() {
	local s
	for s in build tick desktop resume fps; do
		bash "${LIVE}/install.sh" --step "$s" >/dev/null
	done
}

stop_check_unit() {
	systemctl --user stop "${UNIT}.service" 2>/dev/null || true
}

# Polls the scratch wrapper until it answers (bounded, 15 s).
wait_up() {
	for _ in $(seq 30); do
		curl -fsS "http://127.0.0.1:${CHECK_PORT}/api/state" >/dev/null 2>&1 && return 0
		systemctl --user is-active -q "${UNIT}.service" || return 1
		sleep 0.5
	done
	return 1
}

health() {
	# DATA is global: the EXIT trap runs after this function has returned.
	local bin="${LIVE}/build/cli/bundle/bin/game_research_desktop" base
	[[ -x $bin ]] || die "no wrapper build at ${bin}"
	[[ -s "${LIVE}/build/web/${LOGO}" ]] || die "web build has no logo asset"
	DATA="$(mktemp -d)"
	base="http://127.0.0.1:${CHECK_PORT}"
	stop_check_unit
	trap 'stop_check_unit; rm -rf "$DATA"' EXIT
	systemd-run --user --collect --quiet --unit "$UNIT" \
		-p "WorkingDirectory=${LIVE}" \
		--setenv=GAME_RESEARCH_TEST=1 --setenv=GAME_RESEARCH_ANALYZE=off \
		--setenv=GAME_RESEARCH_DISPLAY=:198 \
		--setenv="GAME_RESEARCH_PORT=${CHECK_PORT}" \
		--setenv="GAME_RESEARCH_DATA=${DATA}" \
		--setenv="GAME_RESEARCH_STEAM_ROOT=${DATA}/steam" \
		--setenv="HOME=${HOME}" --setenv="PATH=/usr/local/bin:/usr/bin" \
		"$bin" --serve-only
	wait_up || die "wrapper never answered on :${CHECK_PORT}"
	curl -fsS "${base}/" | grep -q '<html' || die "page not served"
	curl -fsS "${base}/${LOGO}" | grep -q '<svg' || die "logo not served"
	echo "deploy: OK $(git -C "$LIVE" rev-parse --short HEAD), wrapper answers, logo served"
}

main() {
	case "${1:-}" in
	"") pull && install_live && health ;;
	--check) health ;;
	*) die "usage: deploy.sh [--check]" ;;
	esac
}

main "$@"
