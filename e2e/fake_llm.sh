#!/bin/bash
# Stands in for every model in the E2E ($GAME_RESEARCH_FAKE_LLM).
#   fake_llm.sh <tier> <file>
# haiku fails (exit 1) so the fallback chain is exercised; omniroute answers a
# caption; ollama is never reached; opus answers the synthesis JSON built from
# the template it was pointed at. Every call is logged to llm.log.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
tier="${1:?tier}"
file="${2:?file}"
echo "${tier} $(basename "$file")" >>"${ART}/llm.log"

case "$tier" in
haiku)
	echo "Claude AI usage limit reached" >&2
	exit 1
	;;
omniroute)
	printf '{"screen":"a coloured test field","action":"waiting","prompt":""}\n'
	;;
opus)
	python3 "$(dirname "$0")/fake_synthesis.py" "$file"
	;;
*)
	exit 3
	;;
esac
