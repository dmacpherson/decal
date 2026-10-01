# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
TERM_DESKTOP=com.mitchellh.ghostty.desktop
TERM_CMD="ghostty"
_G="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"; _GI="config-file = decal.conf"
term_source() {
  case $PLATFORM in arch) echo "pkg ghostty" ;; fedora|fedora-atomic) echo "copr scottames/ghostty ghostty" ;; *) echo none ;; esac
}
term_configure() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] write $_G/decal.conf + config-file line"; return 0; }
  mkdir -p "$_G"
  { echo "# managed by decal (terminal module)"
    echo "font-family = $FONT_FAMILY"; echo "font-size = $FONT_SIZE"
    echo "cursor-style = $(case $CURSOR in ibeam) echo bar ;; *) echo "$CURSOR" ;; esac)"
    echo "background-opacity = $OPACITY"
    python3 "$MODULE_DIR/palette.py" "$PALETTE" ghostty; } > "$_G/decal.conf"
  grep -qxF "$_GI" "$_G/config" 2>/dev/null || echo "$_GI" >> "$_G/config"
}
term_unconfigure() {
  [[ $LS_DRY_RUN == 1 ]] && return 0
  rm -f "$_G/decal.conf"
  if [[ -f $_G/config ]]; then grep -vxF "$_GI" "$_G/config" > "$_G/config.tmp" || true; mv "$_G/config.tmp" "$_G/config"; [[ -s $_G/config ]] || rm -f "$_G/config"; fi
  return 0
}
term_configured() { [[ -r $_G/decal.conf ]] && grep -qxF "$_GI" "$_G/config" 2>/dev/null; }
