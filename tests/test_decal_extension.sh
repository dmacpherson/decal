#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
X="$REPO/modules/gnome-extensions/bundled/decal@decal"
# the accent stylesheet generator (pure JS), also against this machine's GNOME stylesheet if it has one
SHELL_CSS=""
if [[ -r /usr/share/gnome-shell/gnome-shell-theme.gresource ]] && command -v gjs >/dev/null; then
  SHELL_CSS="$T_TMP/shell.css"
  gjs -c "const {Gio}=imports.gi; const r=Gio.Resource.load('/usr/share/gnome-shell/gnome-shell-theme.gresource'); print(new TextDecoder().decode(r.lookup_data('/org/gnome/shell/theme/gnome-shell-dark.css',0).toArray()))" > "$SHELL_CSS" 2>/dev/null || SHELL_CSS=""
fi
out=$(gjs -m "$REPO/tests/js/accent_test.js" $SHELL_CSS 2>&1); rc=$?
assert_eq "$rc" "0" "accent generator unit tests"; [[ $rc == 0 ]] || printf '%s\n' "$out"
# the settings schema compiles and has the accent keys
glib-compile-schemas --strict --targetdir="$T_TMP" "$X/schemas" 2>&1; assert_eq "$?" "0" "schema compiles"
for k in accent-enabled accent-color accent-fg-color accent-apps instant-minimize; do assert_contains "$(cat "$X"/schemas/*.xml)" "name=\"$k\"" "schema key $k"; done
assert_contains "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' "$X/metadata.json")" "decal@decal" "metadata uuid"
t_done
