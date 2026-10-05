# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="Icon theme from a source (optionally another theme's folder icons on top)"
ICONS="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
REC="$LS_USER_STATE/icons.installed"
PREV="$LS_USER_STATE/icons.prev"

_src() {
  local a=(--path "$P_path"); if [[ -n $P_ref ]]; then a+=(--ref "$P_ref"); fi
  ls_fetch "$P_source" "${a[@]}" || die "could not fetch icon themes from $P_source"
}
_norm() { printf '%s' "${1// /-}"; }
_themes_in() {  # icon themes (index.theme), skipping cursor-only ones
  find "$1" -maxdepth 2 -name index.theme -printf '%h\n' 2>/dev/null | sort | while IFS= read -r d; do
    if [[ -d $d/cursors && ! -d $d/apps && ! -d $d/places ]]; then continue; fi
    echo "$d"
  done
}
_wanted() { if [[ ${P_install[0]:-all} == all ]]; then return 0; fi; printf '%s\n' "${P_install[@]}" | grep -qxF "$1"; }
# the icon theme to use: generated when another theme's folders go on top, or when GNOME's own UI symbols
# replace the theme's (KDE-style symbolic icons render badly in GNOME)
_final() {
  if [[ -n $P_folders ]]; then echo "$P_theme+$P_folders"
  elif [[ $P_symbolic == adwaita ]]; then echo "$P_theme+adwaita-ui"
  else echo "$P_theme"; fi
}
_warn_inherits() {
  local p d found dirs=("$ICONS" "$(sys_path /usr/local/share/icons)" "$(sys_path /usr/share/icons)") x
  IFS=: read -ra x <<<"${XDG_DATA_DIRS:-}"; for d in "${x[@]}"; do [[ -n $d ]] && dirs+=("$d/icons"); done
  for p in $(sed -n 's/^Inherits=//p' "$ICONS/$P_theme/index.theme" | head -1 | tr ',' ' '); do
    found=0; for d in "${dirs[@]}"; do [[ -d $d/$p ]] && found=1; done
    if (( ! found )); then warn "icon theme '$P_theme' inherits '$p', which isn't installed: some icons may fall back further"; fi
  done
}
module_fetch() { _src >/dev/null; }

module_add() {
  local src d n avail=()
  step "downloading icon themes"
  src=$(_src)
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] install icon themes from $P_source into $ICONS"
    run gsettings set org.gnome.desktop.interface icon-theme "$(_final)"; return 0
  fi
  mkdir -p "$ICONS" "$LS_USER_STATE"; touch "$REC"
  step "installing icon themes"
  while IFS= read -r d; do
    n=$(_norm "$(basename "$d")"); avail+=("$n")
    _wanted "$n" || continue
    install_owned "$ICONS" "$n" "$d" "$REC"
  done < <(_themes_in "$src")
  [[ -d $ICONS/$P_theme ]] || die "icon theme '$P_theme' not found (available: ${avail[*]:-none})"
  # generated themes from earlier runs that are no longer wanted
  while IFS= read -r n; do
    if [[ $n == *+* && $n != "$(_final)" ]]; then rm -rf "${ICONS:?}/$n"; grep -vxF "$n" "$REC" > "$REC.t" || true; mv "$REC.t" "$REC"; fi
  done < <(cat "$REC")
  if [[ $(_final) != "$P_theme" ]]; then
    local fargs=()
    if [[ -n $P_folders ]]; then
      [[ -d $ICONS/$P_folders ]] || die "folders theme '$P_folders' not found (available: ${avail[*]:-none})"
      fargs=(--folders "$ICONS/$P_folders")
    fi
    if [[ $P_symbolic == adwaita ]]; then fargs+=(--no-symbolic); fi
    step "building the combined icon theme"
    python3 "$MODULE_DIR/combine.py" "$ICONS/$P_theme" "$ICONS/$(_final)" "$(_final)" "${fargs[@]}"
    rec_add "$REC" "$(_final)"
  fi
  if have gtk-update-icon-cache; then gtk-update-icon-cache -qf "$ICONS/$(_final)" >/dev/null 2>&1 || true; fi
  _warn_inherits
  gs_save "$PREV" org.gnome.desktop.interface icon-theme
  run gsettings set org.gnome.desktop.interface icon-theme "$(_final)"
}
module_remove() {
  gs_restore "$PREV" org.gnome.desktop.interface
  rec_remove_all "$REC" "$ICONS"
}
module_status() {
  if [[ ! -r $REC ]]; then echo not-installed; return 0; fi
  local cur; cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
  if [[ $cur == "$(_final)" && -d $ICONS/$(_final) ]]; then echo installed; else echo "partial (icon theme is '$cur')"; fi
}
module_stamp() { stamp_theme icons icon-theme "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons"; }   # your theme, bundled when it's in your home
