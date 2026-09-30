# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
# Ptyxis (GNOME's terminal; Bazzite/Fedora default). Settings live in gsettings.
TERM_DESKTOP=org.gnome.Ptyxis.desktop
TERM_CMD="ptyxis --new-window"
PT_PREV="$LS_USER_STATE/terminal-ptyxis.prev"
PT_PAL_DIR="$HOME/.local/share/org.gnome.Ptyxis/palettes"
term_source() {
  if have ptyxis; then echo preinstalled
  elif [[ $PLATFORM == fedora* ]]; then echo "pkg ptyxis"
  else echo "flatpak app.devsuite.Ptyxis"; fi
}
_pt_ok() { gsettings list-keys org.gnome.Ptyxis >/dev/null 2>&1; }
_pt_profile() {   # fails if Ptyxis was never opened (it creates its first profile on launch)
  local u; u=$(gsettings get org.gnome.Ptyxis default-profile-uuid | tr -d "'")
  [[ -n $u ]] || u=$(gsettings get org.gnome.Ptyxis profile-uuids | grep -oE "[0-9a-f]{32}" | head -1)
  [[ -n $u ]] || return 1
  echo "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/$u/"
}
term_configure() {
  _pt_ok || { warn "Ptyxis settings schema not visible on the host (flatpak Ptyxis): set font/palette in its preferences"; return 0; }
  local P="" k; P=$(_pt_profile) || warn "no Ptyxis profile yet (open Ptyxis once, then re-run add): colour palette not set"
  # migrate the manual-test backup (made before this module existed)
  if [[ -e $LS_USER_STATE/terminal-test.prev && ! -e $PT_PREV && $LS_DRY_RUN != 1 ]]; then
    sed 's/^\(palette\|cell-height-scale\)=/profile:\1=/' "$LS_USER_STATE/terminal-test.prev" > "$PT_PREV"
  fi
  if [[ ! -e $PT_PREV && $LS_DRY_RUN != 1 ]]; then
    mkdir -p "$LS_USER_STATE"
    { [[ -n $P ]] && echo "profile:palette=$(gsettings get "$P" palette)"
      for k in font-name use-system-font cursor-shape; do echo "$k=$(gsettings get org.gnome.Ptyxis "$k")"; done; } > "$PT_PREV"
  fi
  run mkdir -p "$PT_PAL_DIR"; run cp "$PALETTE" "$PT_PAL_DIR/decal-$THEME.palette"
  if [[ -n $P ]]; then run gsettings set "$P" palette "decal-$THEME"; fi
  run gsettings set org.gnome.Ptyxis font-name "$FONT"
  run gsettings set org.gnome.Ptyxis use-system-font false
  run gsettings set org.gnome.Ptyxis cursor-shape "$CURSOR"
}
term_unconfigure() {
  run rm -f "$PT_PAL_DIR"/decal-*.palette
  { [[ -r $PT_PREV ]] && _pt_ok; } || return 0
  local P="" k v; P=$(_pt_profile) || true
  while IFS='=' read -r k v; do
    if [[ $k == profile:* ]]; then [[ -n $P ]] && run gsettings set "$P" "${k#profile:}" "$v"; else run gsettings set org.gnome.Ptyxis "$k" "$v"; fi
  done < "$PT_PREV"
  run rm -f "$PT_PREV" "$LS_USER_STATE/terminal-test.prev"
}
term_configured() { _pt_ok || return 0; local P; P=$(_pt_profile) || return 1; [[ $(gsettings get "$P" palette) == "'decal-$THEME'" ]]; }
