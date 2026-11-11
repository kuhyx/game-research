#!/bin/bash
# ============================================================================
# Installs game-research for the current user: system tools, the builds, the
# tick sound, the family icon and the .desktop launcher (StartupWMClass =
# the Chrome window's --class). Never starts the app.
#
# Usage: install.sh [--step deps|build|tick|desktop|bin|hooks]   (default: all)
#   Each step stays well under a minute except `build` (~40 s).
# ============================================================================

set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
readonly REPO
readonly SHARE="${XDG_DATA_HOME:-${HOME}/.local/share}"
readonly APPS_DIR="${SHARE}/applications"
readonly ICON_DIR="${SHARE}/icons/hicolor"
readonly TICK="${SHARE}/game-research/tick.wav"
readonly BIN_DIR="${HOME}/.local/bin"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"

# command -> Arch package. Browser deliberately absent: a policy on this PC
# removes `chromium` after makepkg; the launcher discovers one at runtime.
declare -A PKGS=(
	["ffmpeg"]=ffmpeg ["ffprobe"]=ffmpeg ["sxhkd"]=sxhkd ["dmenu"]=dmenu
	["xrandr"]=xorg-xrandr ["paplay"]=libpulse ["xdotool"]=xdotool
	["Xvfb"]=xorg-server-xvfb ["xvfb-run"]=xorg-server-xvfb ["curl"]=curl
	["desktop-file-validate"]=desktop-file-utils ["xdg-open"]=xdg-utils
	["pre-commit"]=python-pre-commit ["jq"]=jq
)
readonly PKGS

die() {
	echo "install.sh: $*" >&2
	exit 1
}

capped() {
	if [[ -x $CAPPED ]]; then CAP_MEM=4G CAP_CPU_PCT=20 "$CAPPED" "$@"; else "$@"; fi
}

step_deps() {
	local cmd missing=()
	for cmd in "${!PKGS[@]}"; do
		command -v "$cmd" >/dev/null 2>&1 || missing+=("${PKGS[$cmd]}")
	done
	/usr/bin/python3 -c 'import tkinter' 2>/dev/null || missing+=(tk)
	if ((${#missing[@]})); then
		mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)
		sudo pacman -S --needed --noconfirm "${missing[@]}"
	fi
	command -v flutter >/dev/null || die "flutter is not on PATH (expected ~/.local/bin/flutter)"
	echo "deps: ok"
}

step_build() {
	cd "$REPO"
	capped flutter pub get >/dev/null
	capped flutter build web --release --no-web-resources-cdn
	capped dart build cli -t bin/game_research_desktop.dart -o build/cli
	capped dart build cli -t bin/game_research_analyze.dart -o build/analyze
}

# The marker tick: a short procedural click (no sourced audio), FLAC-free WAV
# because paplay plays it directly.
step_tick() {
	mkdir -p "$(dirname "$TICK")"
	ffmpeg -v error -y -f lavfi \
		-i "sine=frequency=1760:duration=0.06,afade=t=out:st=0.02:d=0.04" \
		-ar 48000 "$TICK"
	echo "tick: ${TICK}"
}

step_desktop() {
	local size rendered
	for size in "${REPO}"/assets/icon/hicolor/*/; do
		size="$(basename "$size")"
		install -Dm0644 "${REPO}/assets/icon/hicolor/${size}/game-research.png" \
			"${ICON_DIR}/${size}x${size}/apps/game-research.png"
	done
	rendered="$(mktemp --suffix=.desktop)"
	sed -e "s|@LAUNCHER@|${REPO}/tool/game_research_app.sh|" \
		"${REPO}/tool/game-research.desktop.in" >"$rendered"
	desktop-file-validate "$rendered"
	install -Dm0644 "$rendered" "${APPS_DIR}/game-research.desktop"
	rm -f "$rendered"
	update-desktop-database "$APPS_DIR" 2>/dev/null || true
	gtk-update-icon-cache -q -t "$ICON_DIR" 2>/dev/null || true
	echo "desktop: ${APPS_DIR}/game-research.desktop"
	step_bin
}

# Terminal + dmenu_run ($mod+d lists PATH executables, not .desktop files):
# one symlink per name; the launcher resolves its repo through readlink -f.
step_bin() {
	local name
	mkdir -p "$BIN_DIR"
	for name in playstudy game-research; do
		ln -sfn "${REPO}/tool/game_research_app.sh" "${BIN_DIR}/${name}"
	done
	echo "bin: ${BIN_DIR}/playstudy, ${BIN_DIR}/game-research"
}

step_hooks() {
	(cd "$REPO" && pre-commit install --install-hooks >/dev/null)
	echo "hooks: ok"
}

main() {
	case "${1:-}" in
	"") for s in deps build tick desktop hooks; do "step_${s}"; done ;;
	--step)
		[[ $(type -t "step_${2:-}") == function ]] || die "unknown step '${2:-}'"
		"step_$2"
		;;
	*) die "usage: install.sh [--step deps|build|tick|desktop|bin|hooks]" ;;
	esac
}

main "$@"
