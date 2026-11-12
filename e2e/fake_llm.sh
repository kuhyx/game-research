#!/bin/bash
# Stands in for every model in the E2E ($GAME_RESEARCH_FAKE_LLM).
#   fake_llm.sh <tier> <file> [<file>...]
# haiku fails (exit 1, a usage-limit notice) so the fallback chain is
# exercised; omniroute answers a caption, or for several files one JSON array
# with an object per file (a batch); ollama is never reached; opus answers the
# synthesis or the finish merge built from the template it was pointed at.
# Every call is logged to llm.log.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
tier="${1:?tier}"
shift
file="${1:?file}"
names=()
for f in "$@"; do names+=("$(basename "$f")"); done
echo "${tier} ${names[*]}" >>"${ART}/llm.log"

case "$tier" in
haiku)
	echo "Claude AI usage limit reached" >&2
	exit 1
	;;
omniroute)
	if (($# > 1)); then
		sep=""
		printf '['
		for n in "${names[@]}"; do
			printf '%s{"frame":"%s","screen":"a coloured test field","action":"waiting","prompt":""}' "$sep" "$n"
			sep=","
		done
		printf ']\n'
	else
		printf '{"screen":"a coloured test field","action":"waiting","prompt":""}\n'
	fi
	;;
opus)
	python3 "$(dirname "$0")/fake_synthesis.py" "$file"
	;;
*)
	exit 3
	;;
esac
