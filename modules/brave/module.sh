# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Brave settings its Sync keeps per device (look, toolbar, new tab page, search engines, Brave Origin) and extensions"
# Two files, both partial trees merged by prefs.py: preferences -> <profile>/Preferences (per browser profile),
# local-state -> Local State (browser-wide, e.g. Brave Origin: free on Linux, the same flags its own button sets).
# Brave rewrites them when it closes, so they're only changed while it isn't running.
PREV="$LS_USER_STATE/brave.prev.json"          # each setting's value from before decal
PREV_LS="$LS_USER_STATE/brave-local-state.prev.json"
PREFS_REC="$LS_USER_STATE/brave.prefs-path"   # the Preferences file decal changed: undo goes back to that one
# extensions: Chrome Web Store ids, installed by Brave itself on its next start from a file each in its
# "External Extensions" folder (Chromium's way for other programs to add one); deleting the file uninstalls it
EXT_REC="$LS_USER_STATE/brave.extensions"
WEBSTORE='{"external_update_url": "https://clients2.google.com/service/update2/crx"}'
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
_ext_dir() { local d; d=$(_dir) && echo "$d/External Extensions"; }
_ext_ok() { local d id; (( ${#P_extensions[@]} )) || return 0; d=$(_ext_dir) || return 1; for id in "${P_extensions[@]}"; do [[ -e $d/$id.json ]] || return 1; done; }
_ext_add() {
  (( ${#P_extensions[@]} )) || return 0
  local d id; d=$(_ext_dir) || { warn "Brave hasn't been opened yet: extensions skipped (open it once, then run decal again)"; return 0; }
  _ext_ok && return 0
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] Brave extensions: ${P_extensions[*]}"; return 0; fi
  step "adding Brave extensions (installed when Brave next starts)"
  mkdir -p "$d" "$LS_USER_STATE"
  for id in "${P_extensions[@]}"; do
    [[ $id =~ ^[a-p]{32}$ ]] || { warn "$id is not a Chrome Web Store extension id (32 letters a-p); skipped"; continue; }
    [[ -e $d/$id.json ]] && continue
    echo "$WEBSTORE" > "$d/$id.json"; grep -qxF "$id" "$EXT_REC" 2>/dev/null || echo "$id" >> "$EXT_REC"
  done
}
_ext_remove() {   # _ext_remove [ID...] : decal's extension files (all of them without ids)
  [[ -r $EXT_REC ]] || return 0
  local d id ids=("$@"); d=$(_ext_dir) || d=""
  (( ${#ids[@]} )) || mapfile -t ids < "$EXT_REC"
  for id in "${ids[@]}"; do
    grep -qxF "$id" "$EXT_REC" || continue
    if [[ -n $d ]]; then run rm -f "$d/$id.json"; fi
    if [[ $LS_DRY_RUN != 1 ]]; then grep -vxF "$id" "$EXT_REC" > "$EXT_REC.new" || true; mv "$EXT_REC.new" "$EXT_REC"; fi
  done
  if [[ $LS_DRY_RUN != 1 && ! -s $EXT_REC ]]; then rm -f "$EXT_REC"; fi
}

module_add() {
  _ext_add
  [[ -n $P_preferences || -n $P_local_state ]] || return 0
  _prefs >/dev/null || { warn "Brave hasn't been opened yet: open it once, close it, then run decal again"; return 0; }
  _synced && return 0
  if _running; then warn "close Brave, then run decal again (Brave rewrites its settings when it closes)"; return 0; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] merge Brave settings: $P_preferences $P_local_state"; return 0; fi
  step "applying Brave settings"
  mkdir -p "$LS_USER_STATE"
  local f s p; while IFS=$'\t' read -r f s p; do
    if [[ $p == "$PREV" && ! -e $PREV ]]; then printf '%s\n' "$f" > "$PREFS_REC"; fi   # the first time it's changed
    _py apply "$f" "$s" "$p"
  done < <(_pairs)
}

# remove --only TAG: P_extensions holds only the extensions the tag added
MODULE_CAN_DROP=1
module_drop() { (( ${#P_extensions[@]} )) || return 0; _ext_remove "${P_extensions[@]}"; }

module_remove() {
  _ext_remove
  [[ -r $PREV || -r $PREV_LS ]] || return 0
  if _running; then die "close Brave first (it rewrites its settings when it closes)"; fi
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] restore Brave settings"; return 0; fi
  local f
  if [[ -r $PREV ]]; then
    f=$(cat "$PREFS_REC" 2>/dev/null); [[ -r $f ]] || f=$(_prefs) || f=""   # older records: the profile's choice
    if [[ -n $f ]]; then _py restore "$f" "$PREV"; fi
  fi
  if [[ -r $PREV_LS ]] && f=$(_local_state); then _py restore "$f" "$PREV_LS"; fi
  rm -f "$PREV" "$PREV_LS" "$PREFS_REC"
}

module_status() {
  _prefs >/dev/null || { echo "not-installed (Brave not opened yet)"; return 0; }
  if ! _ext_ok; then echo "partial (extensions not added)"; return 0; fi
  if _synced; then echo installed
  elif _running; then echo "partial (close Brave to apply)"; else echo not-installed; fi
}
# stamp: the per-device settings decal knows, Brave Origin, and the extensions you added from the Web Store
STAMP_LIVE=1
module_stamp() {
  local p d; d=$(_dir) || return 0; p="$d/$P_profile/Preferences"; [[ -r $p ]] || return 0
  if _running; then stamp_note "brave: open, so its settings on disk may be a little behind (close it for an exact stamp)"; fi
  python3 "$LS_REPO/lib/stamp.py" brave --prefs "$p" --local-state "$d/Local State" --to "$STAMP_DIR" 2>"$STAMP_DIR/.brave-note"
  stamp_note "brave: $(sed 's/^# //' "$STAMP_DIR/.brave-note")"; rm -f "$STAMP_DIR/.brave-note"
}
