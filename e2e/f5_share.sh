#!/bin/bash
# F5: the Discord share flow. After F1 + F1-check (a session with 8 markers
# and stills): finish the research, open the report, open "my notes" and tap
# the copy icons; each copy is PASTED into a second, non-headless Chromium on
# the private Xvfb (e2e/paste_page.html), whose paste listener writes what it
# received into its window title. Chromium delivers files OR text per paste,
# so the flow is two pastes: files, then text.
#
#   files  -> 8 files NN_<tag>.jpg, 01.. in order   copy notes 1 files
#   text   -> starts with `**`              copy notes 1 text
#   marker -> 1 file                        copy marker <session> 1
#   short  -> <= 1900 chars, no `|`         copy short (on the draft)

# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
: "${ART:?run through e2e/run.sh}"

readonly PASTE_UNIT=gr-e2e-paste
readonly BROWSER="${GAME_RESEARCH_BROWSER:-/usr/lib/chromium/chromium}"
WID=""
BASE=0

# True while the GUI shows a node with label $1 that is not disabled.
live() { fwd tree | grep -F "\"$1" | grep -vqF '[disabled]'; }

# Copies the wrapper answered with 200.
copies_ok() {
	grep -c '"event":"api","path":"[^"]*copy".*"status":200' "${ART}/data/playstudy.jsonl" || true
}

# Taps $1 (a label prefix) and waits until the wrapper confirms copy number $2
# of this run (BASE: copies of an earlier run stay in the log).
copy_tap() {
	wait_for "live '$1'" 30 || fail "'$1' never became tappable"
	fwd tap "$1" --contains >/dev/null || fail "no '$1' icon"
	wait_for "[[ \$(copies_ok) -ge $((BASE + $2)) ]]" 15 || fail "wrapper never confirmed copy $2 ($1)"
}

start_paste_browser() {
	local profile="${ART}/paste-profile"
	mkdir -p "$profile"
	systemctl --user stop "${PASTE_UNIT}.service" 2>/dev/null || true
	systemd-run --user --collect --quiet --unit "$PASTE_UNIT" \
		--setenv="DISPLAY=${E2E_DISPLAY}" \
		"$BROWSER" --user-data-dir="$profile" --mute-audio --disable-extensions \
		--no-first-run --disable-gpu --window-size=900,600 \
		"--app=file://${E2E_REPO}/e2e/paste_page.html"
	WID="$(DISPLAY="$E2E_DISPLAY" timeout 20 xdotool search --sync --onlyvisible --name '^P0:' | head -1)"
	[[ -n $WID ]] || fail "the paste window never showed"
}

# Ctrl+V into the paste window, then judge paste number $1 with the rest.
paste_check() {
	local n="$1" title
	shift
	DISPLAY="$E2E_DISPLAY" xdotool windowfocus --sync "$WID"
	xkey ctrl+v
	wait_for "[[ \$(DISPLAY=${E2E_DISPLAY} xdotool getwindowname ${WID}) == P${n}:* ]]" 5 ||
		fail "paste ${n} never reached the page"
	title="$(DISPLAY="$E2E_DISPLAY" xdotool getwindowname "$WID")"
	python3 "${E2E_REPO}/e2e/check_paste.py" --title "$title" --n "$n" "$@" ||
		fail "paste ${n} is wrong (title ${title:0:80})"
}

session="$(dirname "$(find "${ART}/data" -mindepth 2 -maxdepth 2 -name markers.jsonl | sort | tail -1)")"
BASE="$(copies_ok)"
step "session with 8 markers"
[[ $(wc -l <"${session}/markers.jsonl") -eq 8 ]] || fail "no 8-marker session; run F1 and F1-check first"

step "fresh page (a rerun may find a panel open)"
fwd eval 'location.reload()' >/dev/null || fail "reload failed"
fwd wait "$E2E_GAME" --timeout 30 >/dev/null || fail "game tile never showed"

step "finish the research (the report)"
fwd tap "finished ${E2E_APPID}" --contains >/dev/null || fail "no finish flag"
fwd wait "finished ${E2E_APPID} done" --timeout 40 >/dev/null || fail "finish job never reached done"

step "open the report, then my notes"
fwd tap "finished ${E2E_APPID} done" >/dev/null || fail "report did not open"
# A click in the strip at the top edge slides the reader toolbar in.
wait_for "fwd tap-xy 900 3 >/dev/null 2>&1 && fwd wait 'my notes' --timeout 1 >/dev/null 2>&1" 10 ||
	fail "toolbar never showed"
fwd tap "my notes" >/dev/null || fail "no my notes icon"

step "paste window"
start_paste_browser

step "copy notes 1 files, paste: 8 stills"
copy_tap "copy notes 1 files" 1
paste_check 1 --files 8 --ordered --names '0[1-8]_(good|bad|confusing|note)\.jpg'

step "copy notes 1 text, paste: starts with **"
copy_tap "copy notes 1 text" 2
paste_check 2 --files 0 --text-prefix '**'

step "copy one marker, paste: 1 still"
copy_tap "copy marker" 3
paste_check 3 --files 1 --names 'm_\d\d_\w+\.jpg'

step "copy short on the draft, paste: <= 1900 chars, no |"
fwd tap close >/dev/null || fail "no close on the notes"
fwd key Escape >/dev/null || fail "Esc did not close the report"
fwd tap "draft $(basename "$session")" >/dev/null || fail "no draft button"
wait_for "fwd tap-xy 900 3 >/dev/null 2>&1 && fwd wait 'copy short' --timeout 1 >/dev/null 2>&1" 10 ||
	fail "toolbar never showed on the draft"
copy_tap "copy short" 4
paste_check 4 --files 0 --text-max 1900 --text-forbid '|'

step "stop the paste window"
systemctl --user stop "${PASTE_UNIT}.service"
echo "PASS F5 (4 pastes)"
