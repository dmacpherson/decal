# shellcheck shell=bash disable=SC2034,SC2154  # sourced: vars read by the runner; helpers/vars from lib/ and config.sh
TERM_DESKTOP=org.wezfurlong.wezterm.desktop
_WMARK="-- managed by decal (terminal module)"
term_source() { [[ $PLATFORM == arch ]] && echo "pkg wezterm" || echo "flatpak org.wezfurlong.wezterm"; }
if [[ ${PLATFORM:-} == arch ]]; then TERM_CMD="wezterm"; _W="${XDG_CONFIG_HOME:-$HOME/.config}/wezterm"
else TERM_CMD="flatpak run org.wezfurlong.wezterm"; _W="$HOME/.var/app/org.wezfurlong.wezterm/config/wezterm"; fi
term_configure() {
  [[ $LS_DRY_RUN == 1 ]] && { log "[dry-run] write $_W/colors/decal.toml (+ wezterm.lua if absent)"; return 0; }
  mkdir -p "$_W/colors"
  python3 "$MODULE_DIR/palette.py" "$PALETTE" wezterm > "$_W/colors/decal.toml"
  local cur; cur=$(case $CURSOR in ibeam) echo SteadyBar ;; block) echo SteadyBlock ;; *) echo SteadyUnderline ;; esac)
  if [[ ! -e $_W/wezterm.lua ]]; then
    cat > "$_W/wezterm.lua" <<EOF
$_WMARK
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
config.color_scheme_dirs = { wezterm.config_dir .. '/colors' }
config.color_scheme = 'decal'
config.font = wezterm.font '$FONT_FAMILY'
config.font_size = $FONT_SIZE
config.default_cursor_style = '$cur'
return config
EOF
  elif [[ $(head -1 "$_W/wezterm.lua") != "$_WMARK" ]]; then
    warn "you have your own $_W/wezterm.lua; add: config.color_scheme_dirs = { wezterm.config_dir .. '/colors' }; config.color_scheme = 'decal'"
  fi
}
term_unconfigure() {
  [[ $LS_DRY_RUN == 1 ]] && return 0
  rm -f "$_W/colors/decal.toml"
  [[ $(head -1 "$_W/wezterm.lua" 2>/dev/null) == "$_WMARK" ]] && rm -f "$_W/wezterm.lua"
  return 0
}
term_configured() { [[ -r $_W/colors/decal.toml ]]; }
