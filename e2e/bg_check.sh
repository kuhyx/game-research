#!/bin/bash
# Prints, for every process of the e2e stack (Xvfb, wrapper, chromium, ffmpeg,
# steam/game units), its cpu affinity and scheduling policy, and fails when one
# is not on the background CCD at SCHED_IDLE. Usage: e2e/bg_check.sh [--print]
# shellcheck source=e2e/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check() {
	local mode="${1:-}" unit cg pid cpus pol comm bad=0 n=0
	for unit in $(systemctl --user list-units --plain --no-legend --state=active \
		'gr-e2e-*' 'fwd-game-research-e2e*' 'playstudy-*' | awk '{print $1}'); do
		cg="$(systemctl --user show -p ControlGroup --value "$unit")"
		[[ -r /sys/fs/cgroup${cg}/cgroup.procs ]] || continue
		while read -r pid; do
			cpus="$(awk '/^Cpus_allowed_list/ {print $2}' "/proc/${pid}/status" 2>/dev/null)" || continue
			pol="$(chrt -p "$pid" 2>/dev/null | head -1 | sed 's/.*policy: //')" || continue
			comm="$(cat "/proc/${pid}/comm" 2>/dev/null)" || continue
			n=$((n + 1))
			printf '%-22s %-7s %-16s %-14s %s\n' "$unit" "$pid" "$comm" "$cpus" "$pol"
			[[ $cpus == "$E2E_BG_CPUS" && $pol == SCHED_IDLE ]] || bad=$((bad + 1))
		done <"/sys/fs/cgroup${cg}/cgroup.procs"
	done
	[[ $mode == --print ]] && return 0
	((n > 0)) || fail "bg_check found no process"
	((bad == 0)) || fail "${bad} process(es) outside ${E2E_BG_CPUS} or not SCHED_IDLE"
}

check "$@"
