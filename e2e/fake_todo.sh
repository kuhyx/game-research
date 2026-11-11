#!/bin/bash
# Stands in for the todo CLI in the E2E: logs its argv (one per line) and
# stdin to todo.log instead of creating a real task in kuhy's todo app.

set -euo pipefail

readonly ART="${GAME_RESEARCH_E2E_ART:?}"
{
	printf 'ARG %s\n' "$@"
	printf 'STDIN '
	cat
	echo
} >>"${ART}/todo.log"
echo "e2e00000"
