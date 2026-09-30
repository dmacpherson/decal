#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_DATA_HOME="$T_TMP/home/.local/share" XDG_DATA_DIRS="$T_TMP/share"
ICONS="$XDG_DATA_HOME/icons"
stub gsettings 'case $1 in get) echo "'"'"'Adwaita'"'"'";; esac'
run_mod() { mod_run icons "module_$1"; }
# KDE-style themes ship their own UI symbols; GNOME draws those badly: give the fixture some
mkdir -p "$PROFILE_DIR/demo-icons/Demo-Icons/actions/16"
echo "<svg>slot-close</svg>" > "$PROFILE_DIR/demo-icons/Demo-Icons/actions/16/window-close-symbolic.svg"
echo "<svg>slot-close-colour</svg>" > "$PROFILE_DIR/demo-icons/Demo-Icons/actions/16/window-close.svg"
echo x > "$PROFILE_DIR/demo-icons/Demo-Icons/actions/16/go-next-symbolic-rtl.svg"; echo x > "$PROFILE_DIR/demo-icons/Demo-Icons/actions/16/emblem-symbolic-link.svg"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "add rc"
C="$ICONS/Demo-Icons+Demo-Folders"
for t in Demo-Icons Demo-Folders Demo-Spaced-Icons; do assert_file "$ICONS/$t/index.theme" "installed $t"; done
assert_eq "$(readlink "$C/apps/48/app.svg")" "$ICONS/Demo-Icons/apps/48/app.svg" "base icons are symlinks (no copy)"
assert_nofile "$C/actions/16/window-close-symbolic.svg" "theme's UI symbols left out (symbolic = adwaita by default)"
assert_file "$C/actions/16/window-close.svg" "full-colour icons kept"
assert_nofile "$C/actions/16/go-next-symbolic-rtl.svg" "right-to-left UI symbols left out too"
assert_file "$C/actions/16/emblem-symbolic-link.svg" "an icon merely named 'symbolic-link' is kept"
assert_contains "$(grep '^Inherits=' "$C/index.theme")" "Inherits=Adwaita," "GNOME's UI symbols come first"
assert_eq "$(cat "$C/places/48/folder.svg")" "<svg>green-folder</svg>" "folder icons from the folders theme"
assert_eq "$(cat "$C/places/48/user-home.svg")" "<svg>base-home</svg>" "other places icons from the base"
assert_contains "$(cat "$C/index.theme")" "Name=Demo-Icons+Demo-Folders" "index.theme renamed"
assert_contains "$(grep '^Directories=' "$C/index.theme")" "places/96" "folders theme's extra dirs merged"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface icon-theme Demo-Icons+Demo-Folders" "icon theme set"
assert_contains "$out" "inherits 'hicolor'" "warns about a missing inherited theme"
# without folders, GNOME UI symbols still need a generated theme
sed -i 's/^folders = "Demo-Folders"$/folders = ""/' "$PROFILE_DIR/profile.toml"; : > "$STUBS/calls"
run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface icon-theme Demo-Icons+adwaita-ui" "no folders: generated adwaita-ui theme"
assert_nofile "$ICONS/Demo-Icons+adwaita-ui/actions/16/window-close-symbolic.svg" "no folders: UI symbols left out too"
# symbolic = "theme": the theme is used as is; switching folders off leaves just the base
sed -i 's/^folders = ""$/&\nsymbolic = "theme"/' "$PROFILE_DIR/profile.toml"; : > "$STUBS/calls"
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
