#!/bin/bash
# F5-shots: 3840x2160 screenshots (kuhy's 4K monitor) of the reader toolbar
# and the "my notes" view, after F5 finished the research. The GUI browser is
# restarted at that size (headless, private profile, never kuhy's display).
#
#   SHOTS_DIR=<dir> e2e/run.sh F5-shots     (default: <run>/shots)

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"
readonly OUT="${SHOTS_DIR:-${ART}/shots}"
mkdir -p "$OUT"

step "GUI at 3840x2160"
fwd stop >/dev/null 2>&1 || true
fwd start --url "http://127.0.0.1:${E2E_PORT}/" --profile "${ART}/profile-4k" \
	--cdp-port "$E2E_CDP" --size 3840x2247 >/dev/null # +87 px of window chrome: viewport 3840x2160
fwd wait "$E2E_GAME" --timeout 30 >/dev/null || fail "game tile never showed"

step "report, toolbar out"
fwd tap "finished ${E2E_APPID} done" >/dev/null || fail "report did not open"
wait_for "fwd tap-xy 900 3 >/dev/null 2>&1 && fwd wait 'my notes' --timeout 1 >/dev/null 2>&1" 10 ||
	fail "toolbar never showed"
sleep 1
fwd shot "${OUT}/reader-toolbar-3840x2160.png" >/dev/null || fail "no toolbar shot"

step "my notes"
fwd tap "my notes" >/dev/null || fail "no my notes icon"
fwd wait "copy notes 1 files" --timeout 20 >/dev/null || fail "notes never showed"
sleep 4
fwd shot "${OUT}/notes-3840x2160.png" >/dev/null || fail "no notes shot"
echo "PASS F5-shots ${OUT}"
