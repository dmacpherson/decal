# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Mouse cursor theme from a source (default: Material Bibata), also on the login screen"
MODULE_NEEDS_ROOT=1
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
REC="$LS_USER_STATE/cursor.installed"
PREV="$LS_USER_STATE/cursor.prev"
LOGIN_DIR=/usr/local/share/icons

_src() {
  local a=() x
  for x in "${P_asset[@]}"; do a+=(--asset "$x"); done
  if [[ -n $P_path ]]; then a+=(--path "$P_path"); fi
  ls_fetch "$P_source" "${a[@]}" --version "$P_version" || die "could not fetch cursor themes from $P_source"
}
_themes_in() { find "$1" -name index.theme -printf '%h\n' 2>/dev/null | while IFS= read -r d; do if [[ -d $d/cursors ]]; then echo "$d"; fi; done | sort; }
_ours() { grep -qxF "$1" "$REC" 2>/dev/null; }
module_fetch() { _src >/dev/null; }

_login_add() {
  if [[ $(gdm_mode) == none ]]; then warn "no GDM: login-screen cursor skipped"; return 0; fi
  local cur; cur=$(cat "$LS_STATE/cursor/login-theme" 2>/dev/null || true)
  if [[ -n $cur && $cur != "$P_theme" ]]; then _login_remove; fi
  [[ $LS_DRY_RUN == 1 || -d $ICONS/$P_theme ]] || die "cursor theme '$P_theme' is not installed in $ICONS"
  local dst; dst=$(sys_path "$LOGIN_DIR/$P_theme")
  if [[ -e $dst && $cur != "$P_theme" ]]; then
    warn "$LOGIN_DIR/$P_theme already exists and isn't from decal: the login screen uses it as is"
  else
    srun mkdir -p "$(sys_path "$LOGIN_DIR")"
    srun rm -rf "$dst"
    srun cp -r "$ICONS/$P_theme" "$dst"   # plain copy: root-owned, labelled for /usr/local
    if have restorecon; then srun restorecon -R "$dst" || true; fi
    printf '%s\n' "$P_theme" | swrite "$LS_STATE/cursor/login-theme"
  fi
  gdm_set cursor org/gnome/desktop/interface cursor-theme "'$P_theme'" cursor-size "$P_size"
}
_login_remove() {
  local t; t=$(cat "$LS_STATE/cursor/login-theme" 2>/dev/null || true)
  if [[ -n $t ]]; then srun rm -rf "$(sys_path "$LOGIN_DIR/$t")"; srun rm -f "$LS_STATE/cursor/login-theme"; fi
  gdm_restore cursor
}

module_add() {
  local src d n avail=()
  src=$(_src)
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] install cursor themes from $P_source into $ICONS; use $P_theme (size $P_size)"
  else
    mkdir -p "$ICONS" "$LS_USER_STATE"
    while IFS= read -r d; do
      n=$(basename "$d"); avail+=("$n")
      if [[ -e $ICONS/$n ]] && ! _ours "$n"; then warn "$ICONS/$n already exists and isn't from decal: left as is"; continue; fi
      rm -rf "${ICONS:?}/$n"; cp -a "$d" "$ICONS/$n"
      _ours "$n" || echo "$n" >> "$REC"
    done < <(_themes_in "$src")
    printf '%s\n' "${avail[@]}" | grep -qxF "$P_theme" || die "cursor theme '$P_theme' not in $P_source (available: ${avail[*]:-none})"
    if [[ ! -e $PREV ]]; then
      { echo "cursor-theme=$(gsettings get org.gnome.desktop.interface cursor-theme)"
        echo "cursor-size=$(gsettings get org.gnome.desktop.interface cursor-size)"; } > "$PREV"
    fi
  fi
  run gsettings set org.gnome.desktop.interface cursor-theme "$P_theme"
  run gsettings set org.gnome.desktop.interface cursor-size "$P_size"
  if [[ $P_login == true ]]; then _login_add; else _login_remove; fi
}
module_remove() {
  local k v n
  _login_remove
  if [[ -r $PREV ]]; then
    while IFS='=' read -r k v; do run gsettings set org.gnome.desktop.interface "$k" "$v"; done < "$PREV"
    run rm -f "$PREV"
  fi
  if [[ -r $REC ]]; then
    while IFS= read -r n; do if [[ -n $n ]]; then run rm -rf "${ICONS:?}/$n"; fi; done < "$REC"
    run rm -f "$REC"
  fi
}
module_status() {
  if [[ ! -r $REC ]]; then echo not-installed; return 0; fi
  local t; t=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  if [[ $t != "$P_theme" || ! -d $ICONS/$P_theme ]]; then echo "partial (cursor theme is '$t')"
  elif [[ $P_login == true && $(gdm_mode) != none ]] && ! gdm_has cursor cursor-theme "'$P_theme'"; then echo "partial (login screen not set)"
  else echo installed; fi
}
