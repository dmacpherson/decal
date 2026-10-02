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
_ours() { grep -qxF "$1" "$REC" 2>/dev/null; }
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
    if [[ -e $ICONS/$n ]] && ! _ours "$n"; then warn "$ICONS/$n already exists and isn't from decal: left as is"; continue; fi
    rm -rf "${ICONS:?}/$n"; cp -a "$d" "$ICONS/$n"
    _ours "$n" || echo "$n" >> "$REC"
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
    _ours "$(_final)" || _final >> "$REC"
  fi
  if have gtk-update-icon-cache; then gtk-update-icon-cache -qf "$ICONS/$(_final)" >/dev/null 2>&1 || true; fi
  _warn_inherits
  if [[ ! -e $PREV ]]; then echo "icon-theme=$(gsettings get org.gnome.desktop.interface icon-theme)" > "$PREV"; fi
  run gsettings set org.gnome.desktop.interface icon-theme "$(_final)"
}
module_remove() {
  local k v n
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
  local cur; cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
  if [[ $cur == "$(_final)" && -d $ICONS/$(_final) ]]; then echo installed; else echo "partial (icon theme is '$cur')"; fi
}
# stamp: the theme you picked, bundled into the stamp if you installed it into your home (the system's own themes
# come with the system: nothing to carry)
module_stamp() {
  have dconf || return 0
  local t d b; t=$(dconf read /org/gnome/desktop/interface/icon-theme 2>/dev/null | tr -d "'"); [[ -n $t ]] || return 0
  for b in "${XDG_DATA_HOME:-$HOME/.local/share}/icons" "$HOME/.icons"; do if [[ -d $b/$t ]]; then d=$b/$t; break; fi; done
  if [[ -z ${d:-} ]]; then stamp_note "icons: $t (comes with the system: not stamped)"; return 0; fi
  stamp_copy "$d" "themes/icons/$t" >/dev/null
  stamp_note "icons: $t (bundled, $(du -sh "$d" 2>/dev/null | cut -f1))"
  printf '[icons]\nsource = "themes/icons"\ntheme = "%s"\n' "$t"
}
