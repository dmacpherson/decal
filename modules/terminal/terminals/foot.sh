# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
TERM_DESKTOP=org.codeberg.dnkl.foot.desktop
TERM_CMD="foot"
_F="${XDG_CONFIG_HOME:-$HOME/.config}/foot"
term_source() { echo "pkg foot"; }
_fi() { echo "include=$_F/decal.ini"; }
term_configure() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] write $_F/decal.ini + include"; return 0; }
  mkdir -p "$_F"
  { echo "# managed by decal (terminal module)"
    echo "[main]"; echo "font=$FONT_FAMILY:size=$FONT_SIZE"
    echo "[cursor]"; echo "style=$(case $CURSOR in ibeam) echo beam ;; *) echo "$CURSOR" ;; esac)"
    python3 "$MODULE_DIR/palette.py" "$PALETTE" foot
    echo "alpha=$OPACITY"; } > "$_F/decal.ini"   # still in the palette's [colors]
  if ! grep -qxF "$(_fi)" "$_F/foot.ini" 2>/dev/null; then   # include must come before any [section]
    { _fi; [[ -f $_F/foot.ini ]] && cat "$_F/foot.ini"; } > "$_F/foot.ini.tmp"; mv "$_F/foot.ini.tmp" "$_F/foot.ini"
  fi
}
term_unconfigure() {
  [[ $LS_DRY_RUN == 1 ]] && return 0
  rm -f "$_F/decal.ini"
  if [[ -f $_F/foot.ini ]]; then grep -vxF "$(_fi)" "$_F/foot.ini" > "$_F/foot.ini.tmp" || true; mv "$_F/foot.ini.tmp" "$_F/foot.ini"; [[ -s $_F/foot.ini ]] || rm -f "$_F/foot.ini"; fi
  return 0
}
term_configured() { [[ -r $_F/decal.ini ]] && grep -qxF "$(_fi)" "$_F/foot.ini" 2>/dev/null; }
