# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
TERM_DESKTOP=kitty.desktop
TERM_CMD="kitty"
_K="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"; _KI="include decal.conf"
term_source() { echo "pkg kitty"; }
term_configure() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] write $_K/decal.conf + include"; return 0; }
  mkdir -p "$_K"
  { echo "# managed by decal (terminal module)"
    echo "font_family $FONT_FAMILY"; echo "font_size $FONT_SIZE"
    echo "cursor_shape $(case $CURSOR in ibeam) echo beam ;; *) echo "$CURSOR" ;; esac)"
    echo "background_opacity $OPACITY"
    python3 "$MODULE_DIR/palette.py" "$PALETTE" kitty; } > "$_K/decal.conf"
  grep -qxF "$_KI" "$_K/kitty.conf" 2>/dev/null || echo "$_KI" >> "$_K/kitty.conf"
}
term_unconfigure() {
  [[ $LS_DRY_RUN == 1 ]] && return 0
  rm -f "$_K/decal.conf"
  if [[ -f $_K/kitty.conf ]]; then grep -vxF "$_KI" "$_K/kitty.conf" > "$_K/kitty.conf.tmp" || true; mv "$_K/kitty.conf.tmp" "$_K/kitty.conf"; [[ -s $_K/kitty.conf ]] || rm -f "$_K/kitty.conf"; fi
  return 0
}
term_configured() { [[ -r $_K/decal.conf ]] && grep -qxF "$_KI" "$_K/kitty.conf" 2>/dev/null; }
