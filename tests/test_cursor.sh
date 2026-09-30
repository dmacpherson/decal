#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_DATA_HOME="$T_TMP/home/.local/share"
ICONS="$XDG_DATA_HOME/icons"; stub dconf
mkdir -p "$DECAL_ROOT/usr/share/dconf/profile"; printf 'user-db:user\nsystem-db:gdm\n' > "$DECAL_ROOT/usr/share/dconf/profile/gdm"
stub gsettings 'case $1 in get) if [[ $3 == cursor-size ]]; then echo 24; else echo "'"'"'Adwaita'"'"'"; fi;; esac'
mkdir -p "$ICONS/Demo-Cursor-Light"; echo mine > "$ICONS/Demo-Cursor-Light/marker"   # the user's own, same name
run_mod() { mod_run cursor "module_$1"; }
assert_eq "$(run_mod status)" "not-installed" "before"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add rc"
assert_file "$ICONS/Demo-Cursor/cursors/left_ptr" "theme installed"
assert_eq "$(cat "$ICONS/Demo-Cursor-Light/marker")" "mine" "user's same-named theme untouched"
assert_contains "$out" "Demo-Cursor-Light already exists" "warns about it"
assert_eq "$(cat "$DECAL_USER_STATE/cursor.installed")" "Demo-Cursor" "records only what it copied"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface cursor-theme Demo-Cursor" "cursor set"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface cursor-size 24" "size set"
assert_file "$DECAL_ROOT/usr/local/share/icons/Demo-Cursor/index.theme" "login copy of the chosen theme"
assert_contains "$(cat "$DECAL_ROOT/etc/dconf/db/gdm.d/95-decal-cursor")" "cursor-theme='Demo-Cursor'" "gdm keyfile"
# bad theme name: fails with the list, never changes the cursor
sed -i 's/^theme = "Demo-Cursor"$/theme = "Nope"/' "$PROFILE_DIR/profile.toml"; : > "$STUBS/calls"
out=$(run_mod add 2>&1); assert_eq "$?" "1" "bad theme rc"
assert_contains "$out" "cursor theme 'Nope' not in" "bad theme message"; assert_contains "$out" "Demo-Cursor" "lists available"
assert_not_contains "$(calls)" "cursor-theme Nope" "cursor untouched on failure"
# unreachable source: fails before any change
sed -i 's/^theme = "Nope"$/theme = "Demo-Cursor"/; s/^source = "demo-cursors"$/source = "github-release:o\/r"/' "$PROFILE_DIR/profile.toml"
export DECAL_GITHUB="http://127.0.0.1:9"; : > "$STUBS/calls"
out=$(run_mod add 2>&1); assert_eq "$?" "1" "offline rc"
assert_contains "$out" "could not fetch cursor themes from github-release:o/r" "offline message"
assert_not_contains "$(calls)" "gsettings set" "nothing changed when the source is unreachable"
unset DECAL_GITHUB; sed -i 's/^source = "github-release:o\/r"$/source = "demo-cursors"/' "$PROFILE_DIR/profile.toml"
# remove: restores the cursor, deletes exactly what it installed, undoes the login part
: > "$STUBS/calls"; run_mod remove
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'" "cursor restored"
assert_nofile "$ICONS/Demo-Cursor" "our theme removed"; assert_file "$ICONS/Demo-Cursor-Light/marker" "user's theme kept"
assert_nofile "$DECAL_ROOT/usr/local/share/icons/Demo-Cursor" "login copy removed"
assert_nofile "$DECAL_ROOT/etc/dconf/db/gdm.d/95-decal-cursor" "gdm keyfile removed"
# an admin's own same-named system theme is used as is, never replaced or deleted
A="$DECAL_ROOT/usr/local/share/icons/Demo-Cursor"; mkdir -p "$A"; echo admin > "$A/marker"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add with an admin's system theme rc"
assert_eq "$(cat "$A/marker")" "admin" "admin's system theme untouched"
assert_contains "$out" "the login screen uses it as is" "says it uses the existing system theme"
assert_contains "$(cat "$DECAL_ROOT/etc/dconf/db/gdm.d/95-decal-cursor")" "cursor-theme='Demo-Cursor'" "login cursor still set"
run_mod remove; assert_file "$A/marker" "admin's system theme kept on remove"
assert_nofile "$DECAL_ROOT/etc/dconf/db/gdm.d/95-decal-cursor" "login cursor key removed even though the copy was skipped"
t_done
