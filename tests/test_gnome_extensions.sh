#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile; MODNAME=gnome-extensions
mkdir -p "$T_TMP/cfg" "$T_TMP/home"; echo "user-db:user" > "$T_TMP/dconf-profile"
export XDG_CONFIG_HOME="$T_TMP/cfg" DCONF_PROFILE="$T_TMP/dconf-profile" DECAL_PLATFORM=fedora HOME="$T_TMP/home"
# every UUID "installed" except blur-my-shell, which EGO serves; bazaar-integration isn't on EGO
stub gnome-extensions 'case $1 in info) [[ $2 == blur-my-shell@aunetx || $2 == bazaar-integration@kolunmi.github.io ]] && exit 1; exit 0;; install|uninstall) exit 0;; esac'
stub curl 'for a; do case $a in *bazaar-integration*) exit 22;; *extension-info*) echo "{\"download_url\":\"/download/x.zip\"}"; exit 0;; esac; done; for a; do [[ $prev == -o ]] && : > "$a"; prev=$a; done'
body() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh
    module_add 2>"$T_TMP/err"
    echo "EN=$(gsettings get org.gnome.shell enabled-extensions)"   # effective: distro defaults may already list them
    echo "LOGO=$([[ -f $HOME/.local/share/decal/icons/gnome-logo-deddda.svg ]] && grep -c 'fill:#deddda' "$HOME/.local/share/decal/icons/gnome-logo-deddda.svg")"
    echo "ICON=$(dconf read /org/gnome/shell/extensions/Logo-menu/custom-icon-path)"
    echo "INST=$(tr '\n' ' ' < "$LS_USER_STATE/gnome-extensions.installed")"
    module_remove 2>/dev/null
    echo "EN2=$(dconf read /org/gnome/shell/enabled-extensions)" )
}
export -f body; export REPO T_TMP MODNAME PROFILE_DIR
out=$(dbus-run-session -- bash -c body 2>/dev/null)
v() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_contains "$(v EN)" "blur-my-shell@aunetx" "enabled merged"
assert_eq "$(v INST)" "blur-my-shell@aunetx " "records only what it installed"
assert_contains "$(cat "$T_TMP/err")" "bazaar-integration@kolunmi.github.io" "warns for non-EGO uuid"
assert_contains "$(calls)" "gnome-extensions install --force" "installs zip"
assert_contains "$(calls)" "gnome-extensions uninstall blur-my-shell@aunetx" "uninstalls own"
assert_not_contains "$(calls)" "gnome-extensions uninstall logomenu" "never system ones"
assert_eq "$(v LOGO)" "7" "logo generated in LOGO_COLOR (7 main fills)"
assert_nofile "$T_TMP/home/.local/share/decal/icons/gnome-logo-deddda.svg" "logo removed on remove"
assert_eq "$(v EN2)" "" "user-db enabled-extensions back to unset"
assert_contains "$(calls)" "https://extensions.gnome.org/extension-info/" "extensions site from profile default"
# installed but not yet loaded (the shell only sees new extensions after logging out and in):
# not downloaded again, recorded once, and status says to log out rather than "not installed"
body2() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh
    mkdir -p "$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx"
    echo "blur-my-shell@aunetx" > "$LS_USER_STATE/gnome-extensions.installed"
    module_add 2>/dev/null
    echo "REC=$(tr '\n' ' ' < "$LS_USER_STATE/gnome-extensions.installed")"
    echo "ST=$(module_status)" )
}
export -f body2
: > "$STUBS/calls"; out=$(dbus-run-session -- bash -c body2 2>/dev/null)
assert_not_contains "$(calls)" "gnome-extensions install" "an installed-but-not-loaded extension isn't downloaded again"
assert_eq "$(grep '^REC=' <<<"$out" | cut -d= -f2-)" "blur-my-shell@aunetx " "recorded once"
assert_contains "$(grep '^ST=' <<<"$out")" "log out" "status: log out to activate, not 'not installed'"
t_done
