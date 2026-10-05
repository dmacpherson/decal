#!/usr/bin/env bash
# decal USB stick: get decal (online, or the copy on this stick), get the profile, open decal's menu. The same on
# every stick; stick.conf next to it says which profile and how. Run by the Decal launcher, or: bash .Decal/start.sh
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INSTALL_URL=${DECAL_INSTALL_URL:-https://dmacpherson.github.io/decal/install}

# double-clicked: no terminal yet, so open one (sudo prompts and the menu need it)
if [[ ! -t 0 && -z ${DECAL_STICK_IN_TERM:-} ]]; then
  export DECAL_STICK_IN_TERM=1
  for t in ptyxis kgx gnome-terminal konsole xfce4-terminal mate-terminal tilix alacritty kitty x-terminal-emulator xterm; do
    command -v "$t" >/dev/null || continue
    case $t in
      ptyxis|gnome-terminal|kgx|tilix) exec "$t" -- bash "$HERE/start.sh" "$@" ;;
      xfce4-terminal|mate-terminal) exec "$t" -x bash "$HERE/start.sh" "$@" ;;
      *) exec "$t" -e bash "$HERE/start.sh" "$@" ;;
    esac
  done
fi

say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m%s\033[0m\n' "$*"; read -rp "Press Enter to close… " _ 2>/dev/null || true; exit 1; }
conf() { sed -n "s/^$1=\([^[:space:]#]*\).*/\1/p" "$HERE/stick.conf" | head -1; }

[[ $(uname -s) == Linux ]] || fail "decal only runs on Linux."
[[ -r $HERE/stick.conf ]] || fail "This stick has no stick.conf: run decal usb to set it up again."
PROFILE=$(conf profile); KEY=$(conf key); MODE=$(conf decal); VER=$(conf version)

# 1. decal
online() {
  local s
  if command -v curl >/dev/null; then s=$(curl -fsSL --connect-timeout 10 "$INSTALL_URL") || return 1
  elif command -v wget >/dev/null; then s=$(wget -qO- --timeout=15 "$INSTALL_URL") || return 1
  else return 1; fi
  [[ -n $s ]] && DECAL_NO_MENU=1 bash -c "$s" decal-install
}
from_copy() {   # 0 installed · 2 no copy · fails (exits) when damaged
  local c=$HERE/decal.tar.gz t rc
  [[ -f $c && -f $c.sha256 ]] || return 2
  [[ $(sha256sum "$c" | cut -d' ' -f1) == "$(cut -d' ' -f1 < "$c.sha256")" ]] \
    || fail "The decal copy on this stick is damaged (checksum): run decal usb on your own machine to refresh it."
  t=$(mktemp); tar -xzf "$c" -O decal/install.sh > "$t" 2>/dev/null || { rm -f "$t"; fail "The decal copy on this stick is damaged: run decal usb to refresh it."; }
  DECAL_ARCHIVE=$c DECAL_ARCHIVE_VERSION=${VER:-local} DECAL_NO_MENU=1 bash "$t"; rc=$?; rm -f "$t"; return $rc
}
NO_NET="No internet, and this stick has no copy of decal: connect to the internet and try again."
case $MODE in
  copy) from_copy; rc=$?; (( rc == 0 )) || { (( rc == 2 )) && fail "This stick has no copy of decal: run decal usb to add one."; fail "Couldn't install decal from this stick (see above)."; } ;;
  online) online || fail "$NO_NET" ;;
  *) if ! online; then
       say "Couldn't check for a newer decal: using the copy on this stick (${VER:-unknown version})"
       from_copy; rc=$?; (( rc == 0 )) || { (( rc == 2 )) && fail "$NO_NET"; fail "Couldn't install decal from this stick (see above)."; }
     fi ;;
esac
DECAL=${DECAL_CMD:-$HOME/.local/bin/decal}
[[ -x $DECAL ]] || DECAL=$(command -v decal) || fail "decal didn't install (see the messages above)."
export DECAL_STICK=$HERE

# 2. the profile (on this machine afterwards: unplugging the stick is fine)
case $PROFILE in
  copy)
    t="${XDG_CACHE_HOME:-$HOME/.cache}/decal/stick-profile.tar.gz"; mkdir -p "$(dirname "$t")"
    active="${XDG_CONFIG_HOME:-$HOME/.config}/decal/profile"
    if [[ $(cat "$active/.decal-source" 2>/dev/null) == "$t" ]] \
       && diff -rq -x .decal-source -x .decal-stamp "$HERE/profile" "$active" >/dev/null 2>&1; then
      say "the profile from this stick is already here"   # nothing to do: no new copy, no backup
    else
      tar -czf "$t" -C "$HERE/profile" . 2>/dev/null || fail "The profile copy on this stick can't be read: run decal usb to refresh it."
      "$DECAL" --no-update use "$t" || fail "Couldn't use the profile on this stick (see above)."
    fi ;;
  *)
    if [[ $KEY == saved ]]; then
      GITHUB_TOKEN=$(tr -d '[:space:]' < "$HERE/key" 2>/dev/null); export GITHUB_TOKEN
      "$DECAL" --no-update use "$PROFILE" \
        || fail "The key on this stick no longer works (revoked or expired): run decal usb on your own machine to give it a new one, or remove .Decal/key to sign in each time."
    else
      "$DECAL" --no-update use "$PROFILE" || fail "Couldn't get $PROFILE (see above)."
    fi ;;
esac

# 3. the menu (stick mode)
exec "$DECAL" --no-update ui
