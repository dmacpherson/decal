# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="GTK theme from a source (GTK3 apps; optional forcing onto libadwaita apps)"
THEMES="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
GTK4="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
REC="$LS_USER_STATE/gtk-theme.installed"
PREV="$LS_USER_STATE/gtk-theme.prev"
G4REC="$LS_USER_STATE/gtk-theme.gtk4"
G4BK="$LS_USER_STATE/gtk4-backup"

_src() {
  local a=(--path "$P_path"); if [[ -n $P_ref ]]; then a+=(--ref "$P_ref"); fi
  ls_fetch "$P_source" "${a[@]}" || die "could not fetch GTK themes from $P_source"
}
_norm() { printf '%s' "${1// /-}"; }
_themes_in() { find "$1" -maxdepth 3 -type d \( -name gtk-3.0 -o -name gtk-4.0 \) -printf '%h\n' 2>/dev/null | sort -u; }
_wanted() { if [[ ${P_install[0]:-all} == all ]]; then return 0; fi; printf '%s\n' "${P_install[@]}" | grep -qxF "$1"; }
_ours() { grep -qxF "$1" "$REC" 2>/dev/null; }
_gtk4_link() {
  local f src="$THEMES/$P_theme/gtk-4.0"
  if [[ ! -d $src ]]; then warn "$P_theme has no gtk-4.0 folder: libadwaita option skipped"; return 0; fi
  mkdir -p "$GTK4" "$G4BK"
  for f in gtk.css gtk-dark.css assets; do
    [[ -e $src/$f ]] || continue
    if { [[ -e $GTK4/$f || -L $GTK4/$f ]]; } && ! grep -qxF "$f" "$G4REC" 2>/dev/null; then mv "$GTK4/$f" "$G4BK/$f"; fi
    ln -sfn "$src/$f" "$GTK4/$f"
    grep -qxF "$f" "$G4REC" 2>/dev/null || echo "$f" >> "$G4REC"
  done
}
_gtk4_unlink() {
  [[ -r $G4REC ]] || return 0
  local f
  while IFS= read -r f; do
    [[ -n $f ]] || continue
    rm -f "$GTK4/$f"
    if [[ -e $G4BK/$f ]]; then mv "$G4BK/$f" "$GTK4/$f"; fi
  done < "$G4REC"
  rm -f "$G4REC"; rmdir "$G4BK" 2>/dev/null || true
}
module_fetch() { _src >/dev/null; }

module_add() {
  local src d n avail=()
  src=$(_src)
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] install GTK themes from $P_source into $THEMES (libadwaita: $P_libadwaita)"
    run gsettings set org.gnome.desktop.interface gtk-theme "$P_theme"; return 0
  fi
  mkdir -p "$THEMES" "$LS_USER_STATE"
  while IFS= read -r d; do
    n=$(_norm "$(basename "$d")"); avail+=("$n")
    _wanted "$n" || continue
    if [[ -e $THEMES/$n ]] && ! _ours "$n"; then warn "$THEMES/$n already exists and isn't from decal: left as is"; continue; fi
    rm -rf "${THEMES:?}/$n"; cp -a "$d" "$THEMES/$n"
    _ours "$n" || echo "$n" >> "$REC"
  done < <(_themes_in "$src")
  [[ -d $THEMES/$P_theme ]] || die "GTK theme '$P_theme' not found (available: ${avail[*]:-none})"
  if [[ ! -e $PREV ]]; then echo "gtk-theme=$(gsettings get org.gnome.desktop.interface gtk-theme)" > "$PREV"; fi
  run gsettings set org.gnome.desktop.interface gtk-theme "$P_theme"
  if [[ $P_libadwaita == true ]]; then _gtk4_unlink; _gtk4_link; else _gtk4_unlink; fi
}
module_remove() {
  local k v n
  if [[ $LS_DRY_RUN != 1 ]]; then _gtk4_unlink; fi
  if [[ -r $PREV ]]; then
    while IFS='=' read -r k v; do run gsettings set org.gnome.desktop.interface "$k" "$v"; done < "$PREV"
    run rm -f "$PREV"
  fi
  if [[ -r $REC ]]; then
    while IFS= read -r n; do if [[ -n $n ]]; then run rm -rf "${THEMES:?}/$n"; fi; done < "$REC"
    run rm -f "$REC"
  fi
}
module_status() {
  if [[ ! -r $REC ]]; then echo not-installed; return 0; fi
  local cur; cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
  if [[ $cur != "$P_theme" ]]; then echo "partial (gtk theme is '$cur')"
  elif [[ $P_libadwaita == true ]]; then echo "installed (+libadwaita)"
  else echo installed; fi
}
