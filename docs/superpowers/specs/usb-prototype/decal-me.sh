#!/usr/bin/env bash
# Put Denis's decal profile on this machine: installs/updates decal, then applies github:dmacpherson/decal-profile.
# The GitHub token is read from decal-token.txt next to this script (asked for and saved there if missing).
# Double-click decal-me at the root of the drive, or run: bash Decal/decal-me.sh [MODULE...]
set -euo pipefail
PROFILE=github:dmacpherson/decal-profile
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOKEN_FILE=$HERE/decal-token.txt

# Started without a terminal (double-clicked)? Reopen in one so sudo/prompts work.
if [[ ! -t 0 && -z ${DECAL_ME_IN_TERM:-} ]]; then
  export DECAL_ME_IN_TERM=1
  self=$HERE/$(basename "${BASH_SOURCE[0]}")
  for t in ptyxis kgx gnome-terminal konsole xfce4-terminal mate-terminal tilix alacritty kitty x-terminal-emulator xterm; do
    command -v "$t" >/dev/null || continue
    case $t in
      ptyxis|gnome-terminal|kgx|tilix) exec "$t" -- bash "$self" "$@" ;;
      xfce4-terminal|mate-terminal) exec "$t" -x bash "$self" "$@" ;;
      *) exec "$t" -e bash "$self" "$@" ;;
    esac
  done
fi

pause() { [[ -n ${DECAL_ME_IN_TERM:-} ]] && read -rp "Press Enter to close..." _ || true; }
trap pause EXIT

if [[ $(uname -s) != Linux ]]; then echo "decal only runs on Linux." >&2; exit 1; fi

tok=${GITHUB_TOKEN:-}
[[ -z $tok && -r $TOKEN_FILE ]] && tok=$(tr -d '[:space:]' < "$TOKEN_FILE")
if [[ -z $tok ]]; then
  read -rsp "GitHub token for dmacpherson/decal-profile: " tok; echo
  [[ -n $tok ]] || { echo "no token given" >&2; exit 1; }
  read -rp "Save it to the USB drive ($TOKEN_FILE)? [Y/n] " a
  [[ ${a,,} == n* ]] || { printf '%s\n' "$tok" > "$TOKEN_FILE"; echo "saved."; }
fi

export GITHUB_TOKEN=$tok
if command -v curl >/dev/null; then get() { curl -fsSL "$1"; }
elif command -v wget >/dev/null; then get() { wget -qO- "$1"; }
else echo "curl or wget is needed" >&2; exit 1; fi

get https://dmacpherson.github.io/decal/install | bash -s -- "$PROFILE" "$@"
