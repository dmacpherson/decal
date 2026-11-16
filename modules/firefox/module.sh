# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Firefox settings not carried by Firefox Sync (about:config prefs, search engines, containers, CSS, extensions)"
MODULE_NEEDS_ROOT=1   # policies.json for native (/etc/firefox) and system Flatpak (/var/lib/flatpak) uses root

PREV="$LS_USER_STATE/firefox.prev.json"
PROF_REC="$LS_USER_STATE/firefox.profile-path"
BK_DIR="$LS_USER_STATE/firefox-files"
POL_REC="$LS_USER_STATE/firefox.policy-targets"
USER_POL_BK="$LS_USER_STATE/firefox-user-policies"

_py() { python3 "$MODULE_DIR/prefs.py" "$@"; }

_base_dir() {
  local d
  for d in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox" \
    "$HOME/.mozilla/firefox" \
    "$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox" \
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox"; do
    if [[ -d $d ]]; then echo "$d"; return 0; fi
  done
  return 1
}

_profile_dir() {
  local d
  d=$(_base_dir) || return 1
  _py resolve-profile "$d" "$P_profile" 2>/dev/null
}

_prefs_js() {
  local p
  p=$(_profile_dir) && [[ -r $p/prefs.js ]] && echo "$p/prefs.js"
}

_running() {
  local fp=""
  have flatpak && fp=$(flatpak ps --columns=application 2>/dev/null || true)
  grep -qx org.mozilla.firefox <<<"$fp" || pgrep -x 'firefox|firefox-bin' >/dev/null 2>&1
}

_fp_arch() {
  local arch=""
  if have flatpak; then arch=$(flatpak --default-arch 2>/dev/null || true); fi
  printf '%s\n' "${arch:-$(uname -m)}"
}

# Print "IS_ROOT<tab>PATH" for each installed Firefox policy location (native and/or Flatpak)
_policy_targets() {
  local arch found=0
  arch=$(_fp_arch)
  if have firefox || [[ -d $(sys_path /etc/firefox) ]]; then
    printf '1\t%s\n' "/etc/firefox/policies/policies.json"
    found=1
  fi
  if { have flatpak && flatpak info --system org.mozilla.firefox >/dev/null 2>&1; } || [[ -d $(sys_path /var/lib/flatpak/app/org.mozilla.firefox) ]]; then
    printf '1\t%s\n' "/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/$arch/stable/policies/policies.json"
    found=1
  fi
  if { have flatpak && flatpak info --user org.mozilla.firefox >/dev/null 2>&1; } || [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/app/org.mozilla.firefox ]]; then
    printf '0\t%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/extension/org.mozilla.firefox.systemconfig/$arch/stable/policies/policies.json"
    found=1
  fi
  (( found )) || return 1
}

_desired_policy() {
  local args=() e
  [[ -n $P_policies ]] && args+=(--policies "$P_policies")
  [[ -n $P_search ]] && args+=(--search "$P_search")
  for e in "${P_extensions[@]}"; do args+=(--ext "$e"); done
  (( ${#args[@]} )) || return 1
  _py build-policy "${args[@]}"
}

_policy_synced() {
  local want target is_root path check_path
  want=$(_desired_policy) || return 0
  target=0
  while IFS=$'\t' read -r is_root path; do
    [[ -n $path ]] || continue
    target=1
    if [[ $is_root == 1 ]]; then check_path=$(sys_path "$path"); else check_path=$path; fi
    _py policy-matches "$check_path" <<<"$want" || return 1
  done < <(_policy_targets 2>/dev/null || true)
  (( target )) || return 1
}

_files_synced() {
  local p
  if [[ -n $P_prefs ]]; then
    p=$(_prefs_js) || return 1
    _py prefs-status "$p" "$P_prefs" || return 1
  fi
  if [[ -n $P_containers || -n $P_handlers || -n $P_chrome ]]; then
    p=$(_profile_dir) || return 1
    [[ -n $P_containers ]] && { _py user-file-matches "$P_containers" "$p/containers.json" || return 1; }
    [[ -n $P_handlers ]] && { _py user-file-matches "$P_handlers" "$p/handlers.json" || return 1; }
    [[ -n $P_chrome ]] && { _py user-dir-matches "$P_chrome" "$p/chrome" || return 1; }
  fi
  return 0
}

_synced() {
  _files_synced && _policy_synced
}

_write_policy_file() {
  local is_root=$1 path=$2 content=$3
  if [[ $is_root == 1 ]]; then
    printf '%s\n' "$content" | etc_write firefox "$path"
  else
    local tmp; tmp=$(mktemp "${LS_RUNTMP:-${TMPDIR:-/tmp}}/fx-pol.XXXXXX")
    printf '%s\n' "$content" > "$tmp"
    _py user-install-file "$tmp" "$path" "$USER_POL_BK" "$(printf '%s' "$path" | tr '/' '_')"
    rm -f "$tmp"
  fi
}

_restore_policy_file() {
  local is_root=$1 path=$2
  if [[ $is_root == 1 ]]; then
    etc_restore firefox "$path"
  else
    _py user-restore-file "$path" "$USER_POL_BK" "$(printf '%s' "$path" | tr '/' '_')"
  fi
}

module_add() {
  local policy_json="" has_policy=0
  if [[ -n $P_policies || -n $P_search ]] || (( ${#P_extensions[@]} )); then
    policy_json=$(_desired_policy) || return 1
    [[ -n $policy_json ]] && has_policy=1
  fi

  local has_prof_work=0
  if [[ -n $P_prefs || -n $P_containers || -n $P_handlers || -n $P_chrome ]]; then
    has_prof_work=1
  fi

  if (( has_policy )); then
    local is_root path wrote_any=0
    while IFS=$'\t' read -r is_root path; do
      [[ -n $path ]] || continue
      wrote_any=1
      if [[ $LS_DRY_RUN == 1 ]]; then
        log "[dry-run] write Firefox policy to $path"
      else
        mkdir -p "$LS_USER_STATE"
        grep -qxF "$is_root"$'\t'"$path" "$POL_REC" 2>/dev/null || printf '%s\t%s\n' "$is_root" "$path" >> "$POL_REC"
        _write_policy_file "$is_root" "$path" "$policy_json"
      fi
    done < <(_policy_targets 2>/dev/null || true)
    (( wrote_any )) || warn "Firefox installation not found: policies/extensions skipped"
  fi

  (( has_prof_work )) || return 0
  local pdir
  pdir=$(_profile_dir 2>/dev/null || true)
  if [[ -z $pdir || ( -n $P_prefs && ! -r $pdir/prefs.js ) ]]; then
    warn "Firefox hasn't been opened yet: profile settings skipped (open it once, close it, then run decal again)"
    return 0
  fi

  _files_synced && return 0
  if _running; then
    warn "close Firefox, then run decal again (Firefox rewrites its settings when it closes)"
    return 0
  fi
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] update Firefox profile settings in $pdir"
    return 0
  fi

  step "applying Firefox settings"
  mkdir -p "$LS_USER_STATE"
  if [[ -n $P_prefs ]]; then
    [[ -e $PREV ]] || printf '%s\n' "$pdir/prefs.js" > "$PROF_REC"
    _py prefs-apply "$pdir/prefs.js" "$P_prefs" "$PREV"
  fi
  if [[ -n $P_containers ]]; then
    _py user-install-file "$P_containers" "$pdir/containers.json" "$BK_DIR" containers
  fi
  if [[ -n $P_handlers ]]; then
    _py user-install-file "$P_handlers" "$pdir/handlers.json" "$BK_DIR" handlers
  fi
  if [[ -n $P_chrome ]]; then
    _py user-install-dir "$P_chrome" "$pdir/chrome" "$BK_DIR" chrome
  fi
  return 0
}

# remove --only TAG: P_extensions holds only the extensions the tag added
MODULE_CAN_DROP=1
module_drop() {
  (( ${#P_extensions[@]} )) || return 0
  [[ -r $POL_REC ]] || return 0
  local is_root path check_path updated
  while IFS=$'\t' read -r is_root path; do
    [[ -n $path ]] || continue
    if [[ $is_root == 1 ]]; then check_path=$(sys_path "$path"); else check_path=$path; fi
    [[ -r $check_path ]] || continue
    if [[ $LS_DRY_RUN == 1 ]]; then
      log "[dry-run] drop extensions (${P_extensions[*]}) from $path"
      continue
    fi
    updated=$(_py drop-extensions "$check_path" "${P_extensions[@]}")
    if [[ -n $updated ]]; then
      _write_policy_file "$is_root" "$path" "$updated"
    else
      _restore_policy_file "$is_root" "$path"
    fi
  done < "$POL_REC"
  return 0
}

module_remove() {
  if [[ -r $POL_REC ]]; then
    local is_root path
    while IFS=$'\t' read -r is_root path; do
      [[ -n $path ]] || continue
      if [[ $LS_DRY_RUN == 1 ]]; then
        log "[dry-run] restore Firefox policy $path"
      else
        _restore_policy_file "$is_root" "$path"
      fi
    done < "$POL_REC"
    [[ $LS_DRY_RUN == 1 ]] || rm -rf "$POL_REC" "$USER_POL_BK"
  fi

  local has_prof_state=0
  if [[ -r $PREV || -d $BK_DIR ]]; then has_prof_state=1; fi
  (( has_prof_state )) || return 0

  if _running; then die "close Firefox first (it rewrites its settings when it closes)"; fi
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] restore Firefox profile settings"
    return 0
  fi

  local pdir prefs_f
  pdir=$(_profile_dir 2>/dev/null || true)
  if [[ -r $PREV ]]; then
    prefs_f=$(cat "$PROF_REC" 2>/dev/null || true)
    [[ -r $prefs_f ]] || prefs_f=${pdir:+$pdir/prefs.js}
    if [[ -n $prefs_f && -r $prefs_f ]]; then _py prefs-restore "$prefs_f" "$PREV"; fi
  fi
  if [[ -n $pdir ]]; then
    _py user-restore-file "$pdir/containers.json" "$BK_DIR" containers
    _py user-restore-file "$pdir/handlers.json" "$BK_DIR" handlers
    _py user-restore-dir "$pdir/chrome" "$BK_DIR" chrome
  fi
  rm -rf "$PREV" "$PROF_REC" "$BK_DIR" "$USER_POL_BK"
  return 0
}

module_status() {
  local has_prof_work=0 has_policy=0
  if [[ -n $P_prefs || -n $P_containers || -n $P_handlers || -n $P_chrome ]]; then has_prof_work=1; fi
  if [[ -n $P_policies || -n $P_search ]] || (( ${#P_extensions[@]} )); then has_policy=1; fi

  if (( has_prof_work )) && ! _profile_dir >/dev/null 2>&1; then
    if (( has_policy )) && _policy_synced; then
      echo "partial (Firefox not opened yet)"
    else
      echo "not-installed (Firefox not opened yet)"
    fi
    return 0
  fi

  if (( has_policy )) && ! _policy_synced; then
    if (( has_prof_work )) && _files_synced; then
      echo "partial (policies/extensions not applied)"
    else
      echo "not-installed"
    fi
    return 0
  fi

  if (( has_prof_work )) && ! _files_synced; then
    if _running; then echo "partial (close Firefox to apply)"
    elif (( has_policy )); then echo "partial (profile settings not applied)"
    else echo "not-installed"; fi
    return 0
  fi

  echo "installed"
}

STAMP_LIVE=1
module_stamp() {
  local pdir
  pdir=$(_profile_dir 2>/dev/null || true)
  [[ -n $pdir && -r $pdir/prefs.js ]] || return 0
  if _running; then
    stamp_note "firefox: open, so its settings on disk may be a little behind (close it for an exact stamp)"
  fi
  python3 "$LS_REPO/lib/stamp.py" firefox --profile-dir "$pdir" --to "$STAMP_DIR" 2>"$STAMP_DIR/.firefox-note"
  if [[ -s $STAMP_DIR/.firefox-note ]]; then
    stamp_note "firefox: $(sed 's/^# //' "$STAMP_DIR/.firefox-note")"
  fi
  rm -f "$STAMP_DIR/.firefox-note"
}
