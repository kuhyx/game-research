#!/bin/bash
# Stands in for the tick sound in the E2E: never plays audio, logs the call.

set -euo pipefail

echo "tick $(date +%s.%3N) $*" >>"${GAME_RESEARCH_E2E_ART:?}/tick.log"
