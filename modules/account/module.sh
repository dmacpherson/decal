# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Your account picture (login screen, lock screen, user menu) from an image in your profile"
# Set through AccountsService like GNOME Settings does (no sudo); it keeps its own copy of the image.
PREV="$LS_USER_STATE/account-picture.prev"   # the picture before decal's, as PREV/picture (none: no file inside)
_obj() { busctl call org.freedesktop.Accounts /org/freedesktop/Accounts org.freedesktop.Accounts FindUserByName s "$USER" | awk '{print $2}' | tr -d '"'; }
_icon() { busctl get-property org.freedesktop.Accounts "$(_obj)" org.freedesktop.Accounts.User IconFile | sed -E 's/^s "(.*)"$/\1/'; }
_set() { run busctl call org.freedesktop.Accounts "$(_obj)" org.freedesktop.Accounts.User SetIconFile s "$1"; }   # '' clears it
_current() { local f; f=$(_icon); [[ -r $f ]] && cmp -s "$P_picture" "$f"; }

module_add() {
  [[ -n $P_picture ]] || return 0
  [[ -r $P_picture ]] || die "account picture not found: $P_picture"
  _current && return 0
  if [[ ! -e $PREV && $LS_DRY_RUN != 1 ]]; then
    local f; f=$(_icon); mkdir -p "$PREV"; if [[ -r $f ]]; then cp "$f" "$PREV/picture"; fi
  fi
  step "setting your account picture"
  _set "$(readlink -f "$P_picture")"   # the daemon refuses a path through a link (the active profile usually is one)
}

module_remove() {
  [[ -d $PREV ]] || return 0
  if [[ -r $PREV/picture ]]; then _set "$PREV/picture"; else _set ""; fi
  run rm -rf "$PREV"
}

module_status() {
  if [[ -z $P_picture ]] || _current; then echo installed; else echo not-installed; fi
}
