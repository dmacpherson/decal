#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora HOME="$T_TMP/home" XDG_DATA_HOME="$T_TMP/home/.local/share" XDG_CONFIG_HOME="$T_TMP/home/.config"
T="$XDG_DATA_HOME/themes"; G4="$XDG_CONFIG_HOME/gtk-4.0"
stub gsettings 'case $1 in get) echo "'"'"'Adwaita'"'"'";; esac'
stub flatpak 'exit 1'   # tests never reach Flathub; overridden below
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
# switching to another source: the old source's themes go, the new ones come
run_mod add >/dev/null 2>&1; assert_file "$T/Demo-GTK-Alt/gtk-3.0/gtk.css" "old source installed before switching"
mkdir -p "$PROFILE_DIR/demo-gtk2/Other-GTK/gtk-3.0"; echo "/* other */" > "$PROFILE_DIR/demo-gtk2/Other-GTK/gtk-3.0/gtk.css"
sed -i 's/^source = "demo-gtk"$/source = "demo-gtk2"/; s/^theme = "Demo-GTK"$/theme = "Other-GTK"/' "$PROFILE_DIR/profile.toml"
run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "add from the new source rc"
assert_file "$T/Other-GTK/gtk-3.0/gtk.css" "new source's theme installed"
assert_nofile "$T/Demo-GTK" "old source's themes removed"; assert_nofile "$T/Demo-GTK-Alt" "all of them"
# GitHub release sources pass their asset pattern and version
sed -i 's/^source = "demo-gtk2"$/source = "github-release:o\/r"\nasset = "adw-gtk3*.tar.xz"/' "$PROFILE_DIR/profile.toml"
out=$( (mod_run_pre() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"; echo "$PROFILE_DIR/demo-gtk2"; }; }; mod_run gtk-theme module_add) 2>&1 )
assert_contains "$(calls)" "ls_fetch github-release:o/r --asset adw-gtk3*.tar.xz --version latest" "release asset + version passed"
# Flatpak apps (e.g. Brave) can't see themes in ~/.local/share: the theme's Flathub package makes it visible to them
rm -rf "$DECAL_USER_STATE"/gtk-theme* "$DECAL_STATE/gtk-theme"
sed -i 's/^source = "github-release:o\/r"$/source = "demo-gtk"/; /^asset = /d; s/^theme = "Other-GTK"$/theme = "Demo-GTK"/' "$PROFILE_DIR/profile.toml"
stub flatpak 'case "$*" in "remote-info --system -- flathub org.gtk.Gtk3theme.Demo-GTK") exit 0;; "info --system -- org.gtk.Gtk3theme.Demo-GTK") exit 1;; install*|uninstall*) exit 0;; esac; exit 1'
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "add with the Flatpak package rc"
assert_contains "$(calls)" "flatpak install --system --noninteractive -y -- flathub org.gtk.Gtk3theme.Demo-GTK" "theme's Flatpak package installed"
: > "$STUBS/calls"; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "flatpak uninstall --system --noninteractive -y -- org.gtk.Gtk3theme.Demo-GTK" "and removed with the module"
stub flatpak 'exit 1'
out=$(run_mod add 2>&1)
assert_contains "$out" "Flatpak apps" "no Flathub package: warns that Flatpak apps won't use the theme"
t_done
