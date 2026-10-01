# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Brave settings its Sync keeps per device (look, toolbar, new tab page, search engines, Brave Origin), from files in your profile"
# Two files, both partial trees merged by prefs.py: preferences -> <profile>/Preferences (per browser profile),
# local-state -> Local State (browser-wide, e.g. Brave Origin: free on Linux, the same flags its own button sets).
# Brave rewrites them when it closes, so they're only changed while it isn't running.
PREV="$LS_USER_STATE/brave.prev.json"          # each setting's value from before decal
PREV_LS="$LS_USER_STATE/brave-local-state.prev.json"
_dir() {   # Flatpak or native Brave
  local d
  for d in "$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser" "${XDG_CONFIG_HOME:-$HOME/.config}/BraveSoftware/Brave-Browser"; do
    if [[ -d $d ]]; then echo "$d"; return 0; fi
  done
  return 1
}
_prefs() { local d; d=$(_dir) && [[ -r $d/$P_profile/Preferences ]] && echo "$d/$P_profile/Preferences"; }
_local_state() { local d; d=$(_dir) && [[ -r "$d/Local State" ]] && echo "$d/Local State"; }
_running() {
  { have flatpak && flatpak ps --columns=application 2>/dev/null | grep -qx com.brave.Browser; } || pgrep -x 'brave|brave-browser' >/dev/null 2>&1
}
_py() { python3 "$MODULE_DIR/prefs.py" "$@"; }
_pairs() {   # FILE<tab>SETTINGS<tab>PREV for each file the profile sets
  local f
  if [[ -n $P_preferences ]] && f=$(_prefs); then printf '%s\t%s\t%s\n' "$f" "$P_preferences" "$PREV"; fi
  if [[ -n $P_local_state ]] && f=$(_local_state); then printf '%s\t%s\t%s\n' "$f" "$P_local_state" "$PREV_LS"; fi
}
_synced() { local f s p; while IFS=$'\t' read -r f s p; do _py status "$f" "$s" || return 1; done < <(_pairs); }

module_add() {
  [[ -n $P_preferences || -n $P_local_state ]] || return 0
  _prefs >/dev/null || { warn "Brave hasn't been opened yet: open it once, close it, then run decal again"; return 0; }
  _synced && return 0
  if _running; then warn "close Brave, then run decal again (Brave rewrites its settings when it closes)"; return 0; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] merge Brave settings: $P_preferences $P_local_state"; return 0; fi
  step "applying Brave settings"
  mkdir -p "$LS_USER_STATE"
  local f s p; while IFS=$'\t' read -r f s p; do _py apply "$f" "$s" "$p"; done < <(_pairs)
}

module_remove() {
  [[ -r $PREV || -r $PREV_LS ]] || return 0
  if _running; then die "close Brave first (it rewrites its settings when it closes)"; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] restore Brave settings"; return 0; fi
  local f
  if [[ -r $PREV ]] && f=$(_prefs); then _py restore "$f" "$PREV"; fi
  if [[ -r $PREV_LS ]] && f=$(_local_state); then _py restore "$f" "$PREV_LS"; fi
  rm -f "$PREV" "$PREV_LS"
}

module_status() {
  _prefs >/dev/null || { echo "not-installed (Brave not opened yet)"; return 0; }
  if _synced; then echo installed
  elif _running; then echo "partial (close Brave to apply)"; else echo not-installed; fi
}
