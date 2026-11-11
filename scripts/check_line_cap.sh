#!/bin/bash
# Fails when a source file passed by pre-commit is longer than 250 lines
# (kuhy's global cap: split the file instead of growing it).

set -euo pipefail

readonly CAP=250
status=0
for f in "$@"; do
	lines="$(wc -l <"$f")"
	if ((lines > CAP)); then
		echo "line cap: ${f} has ${lines} lines (max ${CAP})" >&2
		status=1
	fi
done
exit "$status"
