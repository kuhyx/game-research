#!/bin/bash
# ============================================================================
# The Dart test suite, one directory per call (each < 60 s), with coverage.
#
#   scripts/test.sh core|desktop|analysis|app   one directory, coverage file
#                                               coverage/<dir>.info
#   scripts/test.sh coverage                    merge check: every lib/ line
#                                               covered (tool/check_coverage)
#   scripts/test.sh py                          helper + E2E python unit tests
#   scripts/test.sh files <test.dart>...        inner loop: just those files,
#                                               no coverage, killed at 55 s
#
# Flutter's temp files go to .dart_tool/tmp, not /tmp: a full /tmp made a
# test load fail and then hang, holding a machine-wide build slot.
#
# Heavy runs go through ~/.claude/scripts/capped.sh when it exists.
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
export TMPDIR="${REPO}/.dart_tool/tmp"
mkdir -p "$TMPDIR"

capped() {
	if [[ -x $CAPPED ]]; then CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"; else "$@"; fi
}

run_dir() {
	local dir="$1"
	[[ -d "${REPO}/test/${dir}" ]] || {
		echo "test.sh: no test/${dir}" >&2
		exit 2
	}
	# -j1: parallel test isolates under the CPU cap fail to start their DDS.
	(cd "$REPO" && capped flutter test --no-pub -j1 -r failures-only --coverage \
		--coverage-path "coverage/${dir}.info" "test/${dir}")
}

# The named test files only; a hung run is killed before the 60 s cap.
run_files() {
	(($#)) || {
		echo "test.sh: files needs at least one test file" >&2
		exit 2
	}
	(cd "$REPO" && capped timeout --kill-after=3 55 \
		flutter test --no-pub -j1 -r failures-only "$@")
}

case "${1:-}" in
core | desktop | analysis | app) run_dir "$1" ;;
files) shift && run_files "$@" ;;
coverage)
	(cd "$REPO" && dart run tool/check_coverage.dart coverage/*.info)
	;;
py)
	(cd "$REPO" && xvfb-run -a python3 -m pytest -q helpers)
	;;
*)
	echo "usage: scripts/test.sh core|desktop|analysis|app|coverage|py|files <f>..." >&2
	exit 2
	;;
esac
