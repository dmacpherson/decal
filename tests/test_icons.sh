#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_DATA_HOME="$T_TMP/home/.local/share" XDG_DATA_DIRS="$T_TMP/share"
ICONS="$XDG_DATA_HOME/icons"
stub gsettings 'case $1 in get) echo "'"'"'Adwaita'"'"'";; esac'
run_mod() { mod_run icons "module_$1"; }
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add rc"
C="$ICONS/Demo-Icons+Demo-Folders"
for t in Demo-Icons Demo-Folders Demo-Spaced-Icons; do assert_file "$ICONS/$t/index.theme" "installed $t"; done
assert_eq "$(readlink "$C/apps")" "$ICONS/Demo-Icons/apps" "base dirs are symlinks (no copy)"
assert_eq "$(cat "$C/places/48/folder.svg")" "<svg>green-folder</svg>" "folder icons from the folders theme"
assert_eq "$(cat "$C/places/48/user-home.svg")" "<svg>base-home</svg>" "other places icons from the base"
assert_contains "$(cat "$C/index.theme")" "Name=Demo-Icons+Demo-Folders" "index.theme renamed"
assert_contains "$(grep '^Directories=' "$C/index.theme")" "places/96" "folders theme's extra dirs merged"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface icon-theme Demo-Icons+Demo-Folders" "icon theme set"
assert_contains "$out" "inherits 'hicolor'" "warns about a missing inherited theme"
# switching folders off: the generated theme goes away, base becomes the icon theme
sed -i 's/^folders = "Demo-Folders"$/folders = ""/' "$PROFILE_DIR/profile.toml"; : > "$STUBS/calls"
run_mod add >/dev/null 2>&1
assert_nofile "$C" "old generated theme removed on re-add"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface icon-theme Demo-Icons" "base theme set"
# install list limits what is copied
run_mod remove; sed -i 's/^folders = ""$/folders = ""\ninstall = ["Demo-Icons"]/' "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1; assert_nofile "$ICONS/Demo-Folders" "install list respected"
# bad theme
sed -i 's/^theme = "Demo-Icons"$/theme = "Nope"/' "$PROFILE_DIR/profile.toml"
out=$(run_mod add 2>&1); assert_contains "$out" "icon theme 'Nope' not found" "bad theme message"
sed -i 's/^theme = "Nope"$/theme = "Demo-Icons"/' "$PROFILE_DIR/profile.toml"
# remove restores and deletes exactly what it installed
: > "$STUBS/calls"; run_mod remove
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'" "icon theme restored"
assert_nofile "$ICONS/Demo-Icons" "removed"; assert_eq "$(run_mod status)" "not-installed" "status after remove"
t_done
