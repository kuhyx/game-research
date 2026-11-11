#!/bin/bash
# F1 check: waits for the analysis job of the newest session, then asserts the
# MKV (chapters), markers.jsonl offsets (+-0.5 s of the fired input), the
# flash in the recorded frames, frames, clips, contact sheet, captions (which
# tier answered), both drafts in the scratch target and the todo call.

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"

step "newest session"
session="$(find "${ART}/data" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)"
[[ -n $session ]] || fail "no session folder in ${ART}/data"
step "analysis done (<= 50 s)"
status_done() {
	python3 "${E2E_REPO}/e2e/check_session.py" --session "$session" --finished
}
wait_for status_done 50 || fail "analysis still running after 50 s"
step "assert artefacts"
python3 "${E2E_REPO}/e2e/check_session.py" --session "$session" --art "$ART" \
	--expect-markers 8 || fail "check_session.py failed"
echo "PASS F1 ${session}"
