#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile; MODNAME=gnome-settings
mkdir -p "$T_TMP/cfg"; echo "user-db:user" > "$T_TMP/dconf-profile"
export XDG_CONFIG_HOME="$T_TMP/cfg" DCONF_PROFILE="$T_TMP/dconf-profile" DECAL_PLATFORM=fedora
body() {
  cd "$REPO/modules/gnome-settings"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh
    echo "S0=$(module_status)"; module_add 2>/dev/null
    echo "ACC=$(dconf read /org/gnome/desktop/interface/accent-color)"
    echo "FAV=$(dconf read /org/gnome/shell/favorite-apps)"
    echo "TERM=$(dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command)"
    echo "S1=$(module_status)"; module_remove
    echo "ACC2=$(dconf read /org/gnome/desktop/interface/accent-color)"; echo "S2=$(module_status)" )
}
export -f body; export REPO MODNAME PROFILE_DIR
out=$(dbus-run-session -- bash -c body 2>/dev/null)
v() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v S0)" "not-installed" "before"; assert_eq "$(v ACC)" "'purple'" "accent applied"
assert_contains "$(v FAV)" "com.brave.Browser.desktop" "dock applied"; assert_eq "$(v S1)" "installed" "after add"
assert_eq "$(v TERM)" "'ptyxis --new-window'" "@TERMINAL_CMD@ resolved from terminal config"
assert_eq "$(v ACC2)" "" "reset on remove"; assert_eq "$(v S2)" "not-installed" "after remove"
t_done
