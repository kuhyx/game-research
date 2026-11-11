#!/bin/bash
# Screenshots of the GUI at kuhy's real geometry, in a private headless
# chromium (never his display): HDMI-0 2560x1440 at scale 1.25 and DP-2
# 3840x2160 at scale 2, the factors the launcher picks (lib/core/xrandr.dart).
#
#   e2e/screenshot.sh <out dir> [url]     (default url: the E2E wrapper)

set -euo pipefail

readonly OUT="${1:?usage: screenshot.sh <out dir> [url]}"
readonly URL="${2:-http://127.0.0.1:8806/}"
readonly BROWSER="${GAME_RESEARCH_BROWSER:-/usr/lib/chromium/chromium}"

# name, device scale, CSS window size
readonly SHOTS=("hdmi0-2560x1440 1.25 2048,1152" "dp2-3840x2160 2 1920,1080")

shoot() {
	local name="$1" scale="$2" size="$3" profile
	profile="$(mktemp -d)"
	timeout 25 "$BROWSER" --headless=new --disable-extensions --mute-audio \
		--user-data-dir="$profile" --force-device-scale-factor="$scale" \
		--window-size="$size" --hide-scrollbars --virtual-time-budget=15000 \
		--screenshot="${OUT}/${name}.png" "$URL" >/dev/null 2>&1 || true
	rm -rf "$profile"
	[[ -s "${OUT}/${name}.png" ]] || {
		echo "screenshot: ${name} failed" >&2
		exit 1
	}
	echo "${OUT}/${name}.png"
}

mkdir -p "$OUT"
for spec in "${SHOTS[@]}"; do
	read -r name scale size <<<"$spec"
	shoot "$name" "$scale" "$size"
done
