#!/bin/bash
# ============================================================================
# Installs game-research for the current user: system tools, the builds, the
# tick sound, the family icon and the .desktop launcher (StartupWMClass =
# the Chrome window's --class). Never starts the app.
#
# Usage: install.sh [--step deps|build|tick|desktop|bin|resume|hooks|fps]  (default: all)
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
# The resume timer's units (the env seams are for the unit test: a scratch
# folder, and no systemctl).
readonly UNIT_DIR="${GAME_RESEARCH_UNIT_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user}"
readonly CAPPED="${HOME}/.claude/scripts/capped.sh"
readonly DATA="${GAME_RESEARCH_DATA:-${HOME}/data/game-research}"
# Left by the old session-wide MangoHud setup; removed by step_fps.
readonly ENV_D="${XDG_CONFIG_HOME:-${HOME}/.config}/environment.d/60-game-research-mangohud.conf"
readonly XPROFILE="${HOME}/.xprofile"
readonly XP_BEGIN="# >>> game-research mangohud >>>"
readonly XP_END="# <<< game-research mangohud <<<"

# command -> Arch package. Browser deliberately absent: a policy on this PC
# removes `chromium` after makepkg; the launcher discovers one at runtime.
declare -A PKGS=(
	["ffmpeg"]=ffmpeg ["ffprobe"]=ffmpeg ["sxhkd"]=sxhkd ["dmenu"]=dmenu
	["xrandr"]=xorg-xrandr ["paplay"]=libpulse ["xdotool"]=xdotool
	["Xvfb"]=xorg-server-xvfb ["xvfb-run"]=xorg-server-xvfb ["curl"]=curl
	["desktop-file-validate"]=desktop-file-utils ["xdg-open"]=xdg-utils
	["pre-commit"]=python-pre-commit ["jq"]=jq ["xclip"]=xclip
	["gpu-screen-recorder"]=gpu-screen-recorder
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
	# The clipboard helper (helpers/clip_owner.py) needs PyGObject + GTK 3.
	/usr/bin/python3 -c 'import gi; gi.require_version("Gtk", "3.0")' 2>/dev/null ||
		missing+=(python-gobject gtk3)
	# The still captioner (helpers/caption_still.py): Pillow + Noto Sans.
	/usr/bin/python3 -c 'import PIL' 2>/dev/null || missing+=(python-pillow)
	[[ -e /usr/share/fonts/noto/NotoSans-Regular.ttf ]] || missing+=(noto-fonts)
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

# The systemd user timer that relaunches unfinished analysis jobs (shutdown,
# crash, usage limit): 2 min after boot, then every 15 min.
step_resume() {
	mkdir -p "$UNIT_DIR"
	sed -e "s|@REPO@|${REPO}|g" -e "s|@HOME@|${HOME}|g" \
		"${REPO}/tool/systemd/game-research-resume.service.in" \
		>"${UNIT_DIR}/game-research-resume.service"
	install -m0644 "${REPO}/tool/systemd/game-research-resume.timer" "$UNIT_DIR/"
	if [[ -z ${GAME_RESEARCH_NO_SYSTEMCTL:-} ]]; then
		systemctl --user daemon-reload
		systemctl --user enable --now game-research-resume.timer
	fi
	echo "resume: ${UNIT_DIR}/game-research-resume.timer"
}

step_hooks() {
	(cd "$REPO" && pre-commit install --install-hooks >/dev/null)
	echo "hooks: ok"
}

# MangoHud frame-time logging for games only: the package plus the app-owned
# config (no HUD, CSVs into <data>/fps-spool). The wrapper puts the layer into
# each installed game's Steam launch options (lib/desktop/fps_launch.dart).
# Never session-wide: the layer in every Vulkan program aborted sd-cli,
# llama-server and Steam at exit, so the old setup is removed here.
step_fps() {
	local conf="${DATA}/mangohud.conf" spool="${DATA}/fps-spool"
	pacman -Qq mangohud lib32-mangohud >/dev/null 2>&1 ||
		sudo pacman -S --needed --noconfirm mangohud lib32-mangohud
	mkdir -p "$spool"
	sed -e "s|@SPOOL@|${spool}|" "${REPO}/tool/mangohud.conf.in" >"$conf"
	remove_session_mangohud
	echo "fps: ${conf} (games get it through their Steam launch options)"
}

# Undoes the old session-wide layer: environment.d file, the systemd --user
# environment and the ~/.xprofile block. Idempotent; never creates .xprofile.
# unset-environment drops only the set-environment copy; the copy the
# environment.d generator made at login goes on the reload (file now gone).
remove_session_mangohud() {
	rm -f "$ENV_D"
	if [[ -f $XPROFILE ]]; then
		sed -i --follow-symlinks "/^${XP_BEGIN}\$/,/^${XP_END}\$/d" "$XPROFILE"
	fi
	systemctl --user unset-environment MANGOHUD MANGOHUD_CONFIGFILE 2>/dev/null || true
	systemctl --user daemon-reload 2>/dev/null || true
}

main() {
	case "${1:-}" in
	"") for s in deps build tick desktop resume hooks fps; do "step_${s}"; done ;;
	--step)
		[[ $(type -t "step_${2:-}") == function ]] || die "unknown step '${2:-}'"
		"step_$2"
		;;
	*) die "usage: install.sh [--step deps|build|tick|desktop|bin|resume|hooks|fps]" ;;
	esac
}

main "$@"
