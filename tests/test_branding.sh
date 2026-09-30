#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora; stub dconf
mkdir -p "$DECAL_ROOT/usr/share/dconf/profile"; printf 'user-db:user\nsystem-db:gdm\n' > "$DECAL_ROOT/usr/share/dconf/profile/gdm"
run_mod() { mod_run branding "module_$1"; }
f="$DECAL_ROOT/etc/dconf/db/gdm.d/95-decal-branding"
assert_eq "$(run_mod status)" "not-installed" "before"
: > "$STUBS/calls"; run_mod remove; assert_eq "$(calls)" "" "remove never-added: no privileged commands"
run_mod add
assert_eq "$(cat "$f")" $'[org/gnome/login-screen]\nlogo=\'\'' "keyfile (logo hidden)"
assert_contains "$(calls)" "dconf update" "dconf update"; assert_eq "$(run_mod status)" "installed" "after"
run_mod remove; assert_nofile "$f" "removed"; assert_eq "$(run_mod status)" "not-installed" "after remove"
# a custom logo from the profile is copied into state and referenced
sed -i 's/^login-logo = ""/login-logo = "logo.png"/' "$PROFILE_DIR/profile.toml"
run_mod add
assert_file "$DECAL_STATE/branding/logo.png" "logo copied"
assert_contains "$(cat "$f")" "logo='$DECAL_STATE/branding/logo.png'" "keyfile points at the copy"
assert_eq "$(run_mod status)" "installed" "custom logo status"
run_mod remove; assert_nofile "$DECAL_STATE/branding" "copy removed"
sed -i 's/^login-logo = "logo.png"/login-logo = ""/' "$PROFILE_DIR/profile.toml"
# debian path: edits greeter.dconf-defaults, keeps other lines
rm -rf "$DECAL_ROOT/usr/share/dconf"; mkdir -p "$DECAL_ROOT/etc/gdm3"
printf '[org/gnome/login-screen]\n# logo=\nbanner-message-enable=false\n' > "$DECAL_ROOT/etc/gdm3/greeter.dconf-defaults"
run_mod add
assert_contains "$(cat "$DECAL_ROOT/etc/gdm3/greeter.dconf-defaults")" "logo=''" "debian logo set"
assert_contains "$(cat "$DECAL_ROOT/etc/gdm3/greeter.dconf-defaults")" "banner-message-enable=false" "debian keeps rest"
assert_eq "$(run_mod status)" "installed" "debian status"
run_mod remove; assert_contains "$(cat "$DECAL_ROOT/etc/gdm3/greeter.dconf-defaults")" "# logo=" "debian restored"
t_done
