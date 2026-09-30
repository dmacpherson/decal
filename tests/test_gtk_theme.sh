#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_DATA_HOME="$T_TMP/home/.local/share" XDG_CONFIG_HOME="$T_TMP/home/.config"
T="$XDG_DATA_HOME/themes"; G4="$XDG_CONFIG_HOME/gtk-4.0"
stub gsettings 'case $1 in get) echo "'"'"'Adwaita'"'"'";; esac'
run_mod() { mod_run gtk-theme "module_$1"; }
run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "add rc"
assert_file "$T/Demo-GTK/gtk-3.0/gtk.css" "theme installed"; assert_file "$T/Demo-GTK-Alt/gtk-3.0/gtk.css" "all installed"
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface gtk-theme Demo-GTK" "gtk-theme set"
assert_nofile "$G4/gtk.css" "libadwaita off by default: nothing in ~/.config/gtk-4.0"
# libadwaita on: backs up the user's own gtk-4.0 files and links the theme's
mkdir -p "$G4"; echo "/* mine */" > "$G4/gtk.css"
sed -i 's/^theme = "Demo-GTK"$/&\nlibadwaita = true/' "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1
assert_eq "$(readlink "$G4/gtk.css")" "$T/Demo-GTK/gtk-4.0/gtk.css" "gtk.css linked"
assert_eq "$(readlink "$G4/gtk-dark.css")" "$T/Demo-GTK/gtk-4.0/gtk-dark.css" "gtk-dark.css linked"
# turning it off again restores the user's file
sed -i 's/^libadwaita = true$/libadwaita = false/' "$PROFILE_DIR/profile.toml"; run_mod add >/dev/null 2>&1
assert_eq "$(cat "$G4/gtk.css")" "/* mine */" "user's gtk.css restored when libadwaita is switched off"
assert_nofile "$G4/gtk-dark.css" "our link removed"
# remove
: > "$STUBS/calls"; run_mod remove
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'" "restored"
assert_nofile "$T/Demo-GTK" "removed"; assert_eq "$(cat "$G4/gtk.css")" "/* mine */" "user's file still there"
t_done
