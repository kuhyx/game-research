#!/bin/bash
# ============================================================================
# CPU% of one process over a fixed window, from /proc (read-only: safe on a
# live recording during a real play session).
#
#   tool/cpu_sample.sh <pid> [seconds=20]
#
# Prints `<cpu%> <pid> <comm>`; 100 = one core busy. Children not counted.
# ============================================================================

set -euo pipefail

readonly PID="${1:?usage: cpu_sample.sh <pid> [seconds]}"
readonly SECONDS_WINDOW="${2:-20}"
CLK="$(getconf CLK_TCK)"
readonly CLK

# utime + stime (fields 14, 15); comm may hold spaces, so cut after ") ".
ticks() {
	local stat
	stat="$(<"/proc/${PID}/stat")"
	read -r -a f <<<"${stat##*) }"
	echo $((f[11] + f[12]))
}

comm="$(<"/proc/${PID}/comm")"
before="$(ticks)"
sleep "${SECONDS_WINDOW}"
after="$(ticks)"
awk -v d="$((after - before))" -v clk="${CLK}" -v s="${SECONDS_WINDOW}" \
	-v pid="${PID}" -v comm="${comm}" \
	'BEGIN { printf "%.1f %s %s\n", d / clk / s * 100, pid, comm }'
