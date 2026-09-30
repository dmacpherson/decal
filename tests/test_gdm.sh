#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; source "$REPO/lib/common.sh"; LS_REPO="$REPO"
export DECAL_PLATFORM=debian; source "$REPO/lib/platform.sh"; platform_load
F="$DECAL_ROOT/etc/gdm3/greeter.dconf-defaults"; mkdir -p "$(dirname "$F")"
orig=$'[org/gnome/login-screen]\n# logo=\nbanner-message-enable=false\n\n[org/gnome/desktop/interface]\ncursor-size=32'
printf '%s\n' "$orig" > "$F"
assert_eq "$(gdm_mode)" "debian" "debian mode"
# two owners share the file; removing them in either order undoes only each one's own keys
gdm_set branding org/gnome/login-screen logo "''"
gdm_set cursor org/gnome/desktop/interface cursor-theme "'Demo'" cursor-size 24
assert_contains "$(cat "$F")" "logo=''" "branding key set"
assert_contains "$(cat "$F")" "cursor-theme='Demo'" "cursor key set"
gdm_restore branding
assert_not_contains "$(cat "$F")" "logo=''" "branding key gone"
assert_contains "$(cat "$F")" "cursor-theme='Demo'" "cursor keys survive branding's removal"
assert_contains "$(cat "$F")" "cursor-size=24" "cursor size survives"
gdm_restore cursor
assert_eq "$(cat "$F")" "$orig" "file back to the original after both are removed"
# the other order, and a re-set keeps the first recorded previous value
gdm_set cursor org/gnome/desktop/interface cursor-size 24; gdm_set branding org/gnome/login-screen logo "''"
gdm_set cursor org/gnome/desktop/interface cursor-size 48
gdm_restore cursor; assert_contains "$(cat "$F")" "logo=''" "branding survives cursor's removal"
assert_contains "$(cat "$F")" "cursor-size=32" "cursor's first previous value restored"
gdm_restore branding; assert_eq "$(cat "$F")" "$orig" "original again"
t_done
