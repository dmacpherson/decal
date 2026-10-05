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
# extension config files kept outside dconf (e.g. Burn My Windows profiles) come from the profile;
# and an extension decal installed that leaves the list is disabled and uninstalled on the next add
mkdir -p "$PROFILE_DIR/gnome"; printf '[burn-my-windows-profile]\nfire-enable-effect=true\n' > "$PROFILE_DIR/gnome/bmw.conf"
cat >> "$PROFILE_DIR/profile.toml" <<'EOT'
[gnome-extensions.files]
"burn-my-windows/profiles/decal.conf" = "gnome/bmw.conf"
EOT
body3() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    run_add() { ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; module_add 2>/dev/null ); }
    run_rm() { ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; module_remove 2>/dev/null ); }
    F="$XDG_CONFIG_HOME/burn-my-windows/profiles/decal.conf"
    mkdir -p "$(dirname "$F")"; echo "user's own" > "$F"
    echo "blur-my-shell@aunetx" > "$LS_USER_STATE/gnome-extensions.installed"; mkdir -p "$HOME/.local/share/gnome-shell/extensions/blur-my-shell@aunetx"
    run_add
    echo "F1=$(tr '\n' ' ' < "$F")"; echo "MODE=$(stat -c %a "$F")"
    sed -i 's/, "blur-my-shell@aunetx"//' "$PROFILE_DIR/profile.toml"
    run_add
    echo "REC=$(tr '\n' ' ' < "$LS_USER_STATE/gnome-extensions.installed")"
    run_rm
    echo "F2=$(cat "$F")" )
}
export -f body3
: > "$STUBS/calls"; out=$(dbus-run-session -- bash -c body3 2>/dev/null)
v3() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v3 F1)" "[burn-my-windows-profile] fire-enable-effect=true " "profile file copied into ~/.config" 
assert_eq "$(v3 MODE)" "600" "private file mode (like the extension writes it)"
assert_contains "$(calls)" "gnome-extensions disable blur-my-shell@aunetx" "dropped extension disabled"
assert_contains "$(calls)" "gnome-extensions uninstall blur-my-shell@aunetx" "and uninstalled (decal installed it)"
assert_eq "$(v3 REC)" "" "no longer recorded"
assert_eq "$(v3 F2)" "user's own" "remove puts the user's original file back"
# your own panel logo from the profile, recoloured with logo-color like the bundled GNOME logo
printf '<svg xmlns="http://www.w3.org/2000/svg"><g style="fill:#deddda"><circle r="1"/></g></svg>\n' > "$PROFILE_DIR/gnome/mylogo.svg"
sed -i '/^\[gnome-extensions\]$/a logo = "gnome/mylogo.svg"\nlogo-color = "#ff0000"' "$PROFILE_DIR/profile.toml"
body4() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh
    mkdir -p "$HOME/.local/share/decal/icons"; echo old > "$HOME/.local/share/decal/icons/gnome-logo-deddda.svg"
    module_add 2>/dev/null
    echo "ICON=$(dconf read /org/gnome/shell/extensions/Logo-menu/custom-icon-path)"
    echo "FILL=$(grep -c 'fill:#ff0000' "$HOME/.local/share/decal/icons/logo-mylogo-ff0000.svg" 2>/dev/null)"
    echo "OLD=$(ls "$HOME/.local/share/decal/icons/" | tr '\n' ' ')"
    module_remove 2>/dev/null
    echo "LEFT=$(ls "$HOME/.local/share/decal/icons/" 2>/dev/null | tr '\n' ' ')" )
}
export -f body4
out=$(dbus-run-session -- bash -c body4 2>/dev/null)
v4() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v4 ICON)" "'$HOME/.local/share/decal/icons/logo-mylogo-ff0000.svg'" "panel logo points at the profile's logo"
assert_eq "$(v4 FILL)" "1" "recoloured with logo-color"
assert_eq "$(v4 OLD)" "logo-mylogo-ff0000.svg " "the previous logo file is cleaned up"
assert_eq "$(v4 LEFT)" "" "remove deletes it"
# disable: extensions turned off and kept off (even ones the distro turns on); undone on remove
body5() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    gsettings set org.gnome.shell enabled-extensions "['caffeine@patapon.info', 'logomenu@aryan_k']"
    gsettings set org.gnome.shell disabled-extensions "['gsconnect@andyholmes.github.io']"
    sed -i '/^\[gnome-extensions\]$/a disable = ["caffeine@patapon.info", "gsconnect@andyholmes.github.io"]' "$PROFILE_DIR/profile.toml"
    run() { ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; "module_$1" 2>/dev/null ); }
    run add
    echo "EN=$(gsettings get org.gnome.shell enabled-extensions)"; echo "DIS=$(gsettings get org.gnome.shell disabled-extensions)"
    run remove
    echo "EN2=$(gsettings get org.gnome.shell enabled-extensions)"; echo "DIS2=$(gsettings get org.gnome.shell disabled-extensions)"
    sed -i 's/^disable = .*/disable = ["logomenu@aryan_k"]/' "$PROFILE_DIR/profile.toml"
    echo "OVERLAP=$( ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; module_add ) 2>&1 | grep -c 'both enable and disable')" )
}
export -f body5
out=$(dbus-run-session -- bash -c body5 2>/dev/null)
v5() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_not_contains "$(v5 EN)" "caffeine" "disabled extension taken out of enabled-extensions"
assert_contains "$(v5 DIS)" "caffeine@patapon.info" "and put in disabled-extensions"
assert_contains "$(v5 EN2)" "caffeine@patapon.info" "remove turns back on what was on"
assert_contains "$(v5 DIS2)" "gsconnect@andyholmes.github.io" "and leaves off what was already off"
assert_not_contains "$(v5 DIS2)" "caffeine" "caffeine no longer disabled after remove"
assert_eq "$(v5 OVERLAP)" "1" "an extension in both lists is an error"
# extensions bundled with decal install from decal itself, not extensions.gnome.org (sample: demo-ext@decal)
export DECAL_BUNDLED_DIR="$REPO/tests/fixtures/bundled"
body6() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    sed -i 's/^enable = \[/enable = ["demo-ext@decal", /' "$PROFILE_DIR/profile.toml"
    sed -i '/^disable = /d' "$PROFILE_DIR/profile.toml"
    run() { ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; "module_$1" 2>/dev/null ); }
    E="$HOME/.local/share/gnome-shell/extensions/demo-ext@decal"
    run add
    echo "JS=$([[ -f $E/extension.js ]] && echo yes)"; echo "SCHEMA=$([[ -f $E/schemas/gschemas.compiled ]] && echo yes)"
    echo "REC=$(grep -c '^demo-ext@decal$' "$LS_USER_STATE/gnome-extensions.installed")"
    echo "orig" >> "$E/extension.js"; run add; echo "SYNCED=$(grep -c '^orig$' "$E/extension.js")"
    run remove; echo "GONE=$([[ -e $E ]] && echo no || echo yes)" )
}
export -f body6
: > "$STUBS/calls"; out=$(dbus-run-session -- bash -c body6 2>/dev/null)
v6() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v6 JS)" "yes" "bundled extension installed"
assert_eq "$(v6 SCHEMA)" "yes" "its settings schema compiled"
assert_eq "$(v6 REC)" "1" "recorded as installed by decal"
assert_not_contains "$(grep "^curl" "$STUBS/calls")" "demo-ext" "never fetched from extensions.gnome.org"
assert_eq "$(v6 SYNCED)" "0" "a changed copy is re-synced from decal"
assert_eq "$(v6 GONE)" "yes" "remove uninstalls it"
# removing Decal Tweaks also takes its "Apps too" block out of GTK's user stylesheets, keeping the user's own css
body7() {
  cd "$REPO/modules/gnome-extensions"
  ( set -euo pipefail; source "$REPO/lib/common.sh"; LS_REPO="$REPO"; source "$REPO/lib/platform.sh"; platform_load
    sed -i 's/^enable = \[/enable = ["decal@decal", /' "$PROFILE_DIR/profile.toml"
    sed -i '/^disable = /d' "$PROFILE_DIR/profile.toml"
    run() { ( eval "$(python3 "$REPO/lib/profile.py" shell "$MODNAME" --profile "$PROFILE_DIR" --modules "$REPO/modules")"; source ./module.sh; "module_$1" 2>/dev/null ); }
    C="${XDG_CONFIG_HOME:-$HOME/.config}"; mkdir -p "$C/gtk-4.0" "$C/gtk-3.0"
    block=$'/* decal accent: begin (Decal Tweaks) */\n:root { --accent-bg-color: #ff40a0; }\n/* decal accent: end */'
    printf '/* mine */\nwindow { color: red; }\n\n%s\n' "$block" > "$C/gtk-4.0/gtk.css"
    printf '%s\n' "$block" > "$C/gtk-3.0/gtk.css"
    run add; i4=$(stat -c %i "$C/gtk-4.0/gtk.css"); run remove
    echo "SAMEINODE=$([[ $(stat -c %i "$C/gtk-4.0/gtk.css") == "$i4" ]] && echo yes || echo no)"
    echo "MINE=$(grep -c 'mine\|color: red' "$C/gtk-4.0/gtk.css")"; echo "BLOCK4=$(grep -c 'decal accent\|accent-bg' "$C/gtk-4.0/gtk.css")"
    echo "GTK3=$([[ -e $C/gtk-3.0/gtk.css ]] && echo kept || echo gone)" )
}
export -f body7
out=$(DECAL_BUNDLED_DIR=bundled dbus-run-session -- bash -c body7 2>/dev/null)
v7() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v7 MINE)" "2" "removing Decal Tweaks keeps the user's own GTK css"
assert_eq "$(v7 BLOCK4)" "0" "and takes its Apps too block out"
assert_eq "$(v7 SAMEINODE)" "no" "gtk.css replaced whole (never half-written)"
assert_eq "$(v7 GTK3)" "gone" "a stylesheet with only the block goes"
# extensions.gnome.org (or the profile's source) is reached over https only, never redirected to http
assert_not_contains "$(grep '^curl' "$STUBS/calls" | grep -v -- '--proto =https --proto-redir =https')" "extension-info" "every extension download is https only"
# no GNOME Shell (KDE, Xfce…): skipped with a word, the run goes on (audit batch 2)
out=$( ( mod_run_pre() { have() { [[ $1 != gnome-extensions ]] && command -v "$1" >/dev/null 2>&1; }; }; mod_run gnome-extensions module_add ) 2>&1); assert_eq "$?" "0" "no GNOME Shell: not a failure"
assert_contains "$out" "skipped" "...says it's skipped"
t_done
