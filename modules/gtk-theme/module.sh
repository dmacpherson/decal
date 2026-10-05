# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and the profile
MODULE_DESC="GTK theme from a source (GTK3 apps; optional forcing onto libadwaita apps)"
THEMES="${XDG_DATA_HOME:-$HOME/.local/share}/themes"
GTK4="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0"
REC="$LS_USER_STATE/gtk-theme.installed"
PREV="$LS_USER_STATE/gtk-theme.prev"
G4REC="$LS_USER_STATE/gtk-theme.gtk4"
G4BK="$LS_USER_STATE/gtk4-backup"
FPREC="$LS_STATE/gtk-theme/flatpak"   # the theme's Flatpak package, if this module installed it
MODULE_NEEDS_ROOT=1                   # system-wide Flatpak package (next to the apps using it)

_src() {
  local a=() x
  if [[ -n $P_path ]]; then a+=(--path "$P_path"); fi
  if [[ -n $P_ref ]]; then a+=(--ref "$P_ref"); fi
  if (( ${#P_asset[@]} )); then for x in "${P_asset[@]}"; do a+=(--asset "$x"); done; a+=(--version "$P_version"); fi
  ls_fetch "$P_source" "${a[@]}" || die "could not fetch GTK themes from $P_source"
}
_norm() { printf '%s' "${1// /-}"; }
_themes_in() { find "$1" -maxdepth 3 -type d \( -name gtk-3.0 -o -name gtk-4.0 \) -printf '%h\n' 2>/dev/null | sort -u; }
_wanted() { if [[ ${P_install[0]:-all} == all ]]; then return 0; fi; printf '%s\n' "${P_install[@]}" | grep -qxF "$1"; }
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
# Flatpak apps (Brave, ...) only see themes packaged for Flatpak: org.gtk.Gtk3theme.<name> on Flathub,
# which Flatpak hands to every app when the desktop's gtk-theme has that name
_flatpak_theme() {
  have flatpak || return 0
  local want="org.gtk.Gtk3theme.$P_theme" cur; cur=$(cat "$FPREC" 2>/dev/null || true)
  if [[ -n $cur && $cur != "$want" ]]; then _flatpak_theme_remove; fi
  if flatpak info --system -- "$want" >/dev/null 2>&1; then return 0; fi
  if flatpak remote-info --system -- flathub "$want" >/dev/null 2>&1; then
    step "installing $want for Flatpak apps"
    srun flatpak install --system --noninteractive -y -- flathub "$want"
    printf '%s\n' "$want" | swrite "$FPREC"
  else
    warn "Flatpak apps (e.g. Brave) won't use $P_theme: Flathub has no $want"
  fi
}
_flatpak_theme_remove() {
  local id; id=$(cat "$FPREC" 2>/dev/null || true)
  [[ -n $id ]] || return 0
  srun flatpak uninstall --system --noninteractive -y -- "$id" || true
  srun rm -f "$FPREC"
}
module_fetch() { _src >/dev/null; }

module_add() {
  local src d n avail=()
  step "downloading GTK themes"
  src=$(_src)
  if [[ $LS_DRY_RUN == 1 ]]; then
    log "[dry-run] install GTK themes from $P_source into $THEMES (libadwaita: $P_libadwaita)"
    run gsettings set org.gnome.desktop.interface gtk-theme "$P_theme"
    if [[ $P_flatpak == true ]]; then _flatpak_theme; fi
    return 0
  fi
  mkdir -p "$THEMES" "$LS_USER_STATE"
  step "installing GTK themes"
  while IFS= read -r d; do
    n=$(_norm "$(basename "$d")"); avail+=("$n")
    _wanted "$n" || continue
    install_owned "$THEMES" "$n" "$d" "$REC"
  done < <(_themes_in "$src")
  [[ -d $THEMES/$P_theme ]] || die "GTK theme '$P_theme' not found (available: ${avail[*]:-none})"
  # themes installed from an earlier source that this one doesn't have any more
  local keep=""; while IFS= read -r n; do
    if [[ -n $n ]] && ! printf '%s\n' "${avail[@]}" | grep -qxF "$n"; then rm -rf "${THEMES:?}/$n"; else keep+="$n"$'\n'; fi
  done < "$REC"; printf '%s' "$keep" > "$REC"
  gs_save "$PREV" org.gnome.desktop.interface gtk-theme
  run gsettings set org.gnome.desktop.interface gtk-theme "$P_theme"
  if [[ $P_flatpak == true ]]; then _flatpak_theme; else _flatpak_theme_remove; fi
  if [[ $P_libadwaita == true ]]; then _gtk4_unlink; _gtk4_link; else _gtk4_unlink; fi
}
module_remove() {
  _flatpak_theme_remove
  if [[ $LS_DRY_RUN != 1 ]]; then _gtk4_unlink; fi
  gs_restore "$PREV" org.gnome.desktop.interface
  rec_remove_all "$REC" "$THEMES"
}
module_status() {
  if [[ ! -r $REC ]]; then echo not-installed; return 0; fi
  local cur; cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")
  if [[ $cur != "$P_theme" ]]; then echo "partial (gtk theme is '$cur')"
  elif [[ $P_libadwaita == true ]]; then echo "installed (+libadwaita)"
  else echo installed; fi
}
module_stamp() { stamp_theme gtk-theme gtk-theme "${XDG_DATA_HOME:-$HOME/.local/share}/themes" "$HOME/.themes"; }   # your theme, bundled when it's in your home
