# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Brave settings its Sync keeps per device (look, toolbar, new tab page, search engines), from a file in your profile"
# Brave rewrites its Preferences when it closes, so they're only changed while it isn't running (see prefs.py).
PREV="$LS_USER_STATE/brave.prev.json"   # each setting's value from before decal
_dir() {   # Flatpak or native Brave
  local d
  for d in "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "${XDG_CONFIG_HOME:-$HOME/.config}/BraveSoftware/Brave-Browser"; do
    if [[ -d $d ]]; then echo "$d"; return 0; fi
  done
  return 1
}
_prefs() { local d; d=$(_dir) && [[ -r $d/$P_profile/Preferences ]] && echo "$d/$P_profile/Preferences"; }
_running() {
  { have flatpak && flatpak ps --columns=application 2>/dev/null | grep -qx com.brave.Browser; } || pgrep -x 'brave|brave-browser' >/dev/null 2>&1
}
_py() { python3 "$MODULE_DIR/prefs.py" "$@"; }

module_add() {
  [[ -n $P_preferences ]] || return 0
  local f; f=$(_prefs) || { warn "Brave hasn't been opened yet: open it once, close it, then run decal again"; return 0; }
  _py status "$f" "$P_preferences" && return 0
  if _running; then warn "close Brave, then run decal again (Brave rewrites its settings when it closes)"; return 0; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] merge $P_preferences into $f"; return 0; fi
  step "applying Brave settings"
  mkdir -p "$LS_USER_STATE"; _py apply "$f" "$P_preferences" "$PREV"
}

module_remove() {
  [[ -r $PREV ]] || return 0
  local f; f=$(_prefs) || { run rm -f "$PREV"; return 0; }
  if _running; then die "close Brave first (it rewrites its settings when it closes)"; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] restore Brave settings in $f"; return 0; fi
  _py restore "$f" "$PREV"; rm -f "$PREV"
}

module_status() {
  local f; f=$(_prefs) || { echo "not-installed (Brave not opened yet)"; return 0; }
  if [[ -z $P_preferences ]] || _py status "$f" "$P_preferences"; then echo installed
  elif _running; then echo "partial (close Brave to apply)"; else echo not-installed; fi
}
