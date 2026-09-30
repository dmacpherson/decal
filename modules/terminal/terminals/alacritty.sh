# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
TERM_DESKTOP=Alacritty.desktop
TERM_CMD="alacritty"
_A="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"; _AMARK="# managed by decal (terminal module)"
term_source() { echo "pkg alacritty"; }
term_configure() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] write $_A/decal.toml"; return 0; }
  mkdir -p "$_A"
  { echo "$_AMARK"
    printf '[font]\nsize = %s\n\n[font.normal]\nfamily = "%s"\n\n' "$FONT_SIZE" "$FONT_FAMILY"
    printf '[cursor.style]\nshape = "%s"\n\n' "$(case $CURSOR in ibeam) echo Beam ;; block) echo Block ;; *) echo Underline ;; esac)"
    python3 "$MODULE_DIR/palette.py" "$PALETTE" alacritty; } > "$_A/decal.toml"
  if [[ ! -e $_A/alacritty.toml ]]; then
    printf '%s\n[general]\nimport = ["decal.toml"]\n' "$_AMARK" > "$_A/alacritty.toml"
  elif ! grep -qF 'decal.toml' "$_A/alacritty.toml"; then
    warn "you have your own $_A/alacritty.toml; add this under [general] to use the theme: import = [\"decal.toml\"]"
  fi
}
term_unconfigure() {
  [[ $LS_DRY_RUN == 1 ]] && return 0
  rm -f "$_A/decal.toml"
  [[ $(head -1 "$_A/alacritty.toml" 2>/dev/null) == "$_AMARK" ]] && rm -f "$_A/alacritty.toml"
  return 0
}
term_configured() { [[ -r $_A/decal.toml ]] && grep -qF 'decal.toml' "$_A/alacritty.toml" 2>/dev/null; }
