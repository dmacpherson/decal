#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
M="$REPO/modules/terminal"; PAL="$M/themes/cyberpunk/colors.palette"
export HOME="$T_TMP/home" XDG_CONFIG_HOME="$T_TMP/home/.config"; mkdir -p "$XDG_CONFIG_HOME"
# palette conversions
assert_contains "$(python3 "$M/palette.py" "$PAL" kitty)" "color5 #F706CF" "kitty palette"
assert_contains "$(python3 "$M/palette.py" "$PAL" ghostty)" "palette = 6=#00F6FF" "ghostty palette"
assert_contains "$(python3 "$M/palette.py" "$PAL" foot)" "regular5=f706cf" "foot palette"
assert_contains "$(python3 "$M/palette.py" "$PAL" alacritty)" 'magenta = "#F706CF"' "alacritty palette"
assert_contains "$(python3 "$M/palette.py" "$PAL" wezterm)" 'ansi = ["#1A1033"' "wezterm palette"
# each adapter: configure into a user config that already has content, then unconfigure restores it
ad() { ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; PLATFORM=${PLAT:-fedora}; MODULE_DIR="$M"
  THEME=cyberpunk PALETTE="$PAL" FONT="FiraCode Nerd Font 10" FONT_FAMILY="FiraCode Nerd Font" FONT_SIZE=10 CURSOR=underline
  OPACITY=0.75
  source "$M/terminals/$1.sh"; shift; "$@" ); }
mkdir -p "$XDG_CONFIG_HOME/kitty"; echo "# mine" > "$XDG_CONFIG_HOME/kitty/kitty.conf"
ad kitty term_configure
assert_contains "$(cat "$XDG_CONFIG_HOME/kitty/kitty.conf")" "include decal.conf" "kitty include"
assert_contains "$(cat "$XDG_CONFIG_HOME/kitty/decal.conf")" "cursor_shape underline" "kitty cursor"
assert_contains "$(cat "$XDG_CONFIG_HOME/kitty/decal.conf")" "background_opacity 0.75" "kitty opacity"
ad kitty term_configured; assert_eq "$?" "0" "kitty configured"
ad kitty term_unconfigure; assert_eq "$(cat "$XDG_CONFIG_HOME/kitty/kitty.conf")" "# mine" "kitty restored"
ad ghostty term_configure
assert_contains "$(cat "$XDG_CONFIG_HOME/ghostty/decal.conf")" "cursor-style = underline" "ghostty cursor"
assert_contains "$(cat "$XDG_CONFIG_HOME/ghostty/decal.conf")" "background-opacity = 0.75" "ghostty opacity"
ad ghostty term_unconfigure; assert_nofile "$XDG_CONFIG_HOME/ghostty/config" "ghostty created file removed"
mkdir -p "$XDG_CONFIG_HOME/foot"; printf '[main]\nterm=xterm\n' > "$XDG_CONFIG_HOME/foot/foot.ini"
ad foot term_configure; assert_eq "$(head -1 "$XDG_CONFIG_HOME/foot/foot.ini")" "include=$XDG_CONFIG_HOME/foot/decal.ini" "foot include first"
assert_eq "$(awk '/^\[/{s=$0} /^alpha=/{print s, $0}' "$XDG_CONFIG_HOME/foot/decal.ini")" "[colors] alpha=0.75" "foot opacity (alpha in [colors])"
ad foot term_unconfigure; assert_eq "$(cat "$XDG_CONFIG_HOME/foot/foot.ini")" $'[main]\nterm=xterm' "foot restored"
ad alacritty term_configure; assert_contains "$(cat "$XDG_CONFIG_HOME/alacritty/alacritty.toml")" 'import = ["decal.toml"]' "alacritty created"
assert_contains "$(cat "$XDG_CONFIG_HOME/alacritty/decal.toml")" $'[window]\nopacity = 0.75' "alacritty opacity"
ad alacritty term_unconfigure; assert_nofile "$XDG_CONFIG_HOME/alacritty/alacritty.toml" "alacritty removed (ours)"
mkdir -p "$XDG_CONFIG_HOME/alacritty"; echo "# user's" > "$XDG_CONFIG_HOME/alacritty/alacritty.toml"
out=$(ad alacritty term_configure 2>&1); assert_contains "$out" 'import = ["decal.toml"]' "alacritty existing: prints line"
assert_eq "$(cat "$XDG_CONFIG_HOME/alacritty/alacritty.toml")" "# user's" "alacritty existing untouched"
PLAT=fedora ad wezterm term_configure; W="$HOME/.var/app/org.wezfurlong.wezterm/config/wezterm"
assert_contains "$(cat "$W/wezterm.lua")" "SteadyUnderline" "wezterm (flatpak path) cursor"; assert_file "$W/colors/decal.toml" "wezterm scheme"
assert_contains "$(cat "$W/wezterm.lua")" "config.window_background_opacity = 0.75" "wezterm opacity"
PLAT=fedora ad wezterm term_unconfigure; assert_nofile "$W/wezterm.lua" "wezterm removed (ours)"
# sources per platform
assert_eq "$(PLAT=debian ad ghostty term_source)" "none" "ghostty debian"
assert_eq "$(PLAT=fedora-atomic ad ghostty term_source)" "copr scottames/ghostty ghostty" "ghostty fedora"
assert_eq "$(PLAT=arch ad wezterm term_source)" "pkg wezterm" "wezterm arch"
assert_eq "$(PLAT=debian ad wezterm term_source)" "flatpak org.wezfurlong.wezterm" "wezterm debian"
# switching ptyxis -> kitty through the module unconfigures ptyxis and makes kitty the default
export DECAL_PLATFORM=fedora
stub brew 'exit 0'; stub curl 'exit 7'; stub fc-cache; stub ptyxis; stub rpm 'exit 1'; stub dnf
stub gsettings 'case $1 in get) case $3 in default-profile-uuid) echo "'"'"'abc'"'"'";; *) echo "'"'"'gnome'"'"'";; esac;; list-keys) exit 0;; esac'
mkdir -p "$HOME/.bashrc.d" "$HOME/.local/share/blesh" "$HOME/.local/share/fonts/decal/FiraCodeNerdFont"; echo '. ~/.bashrc.d/x' > "$HOME/.bashrc"; : > "$HOME/.local/share/blesh/ble.sh"
mod() { mod_run terminal "$@"; }
mod module_add 2>/dev/null; : > "$STUBS/calls"
sed -i 's/^app = "ptyxis"/app = "kitty"/' "$PROFILE_DIR/profile.toml"; mod module_add 2>/dev/null
assert_contains "$(calls)" "gsettings set org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/abc/ palette 'gnome'" "ptyxis unconfigured"
assert_contains "$(calls)" "dnf install -y kitty" "kitty installed via backend"
assert_eq "$(head -1 "$XDG_CONFIG_HOME/xdg-terminals.list")" "kitty.desktop" "kitty is default"
t_done
