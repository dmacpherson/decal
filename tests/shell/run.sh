#!/usr/bin/env bash
# Runs bundled GNOME Shell extensions in a throwaway headless GNOME Shell (own HOME, own D-Bus session,
# virtual monitor) and checks them from inside the Shell with a probe extension. Needs gnome-shell;
# never touches the running desktop. OUT=DIR keeps the screenshots there; otherwise nothing is left behind.
set -u
repo="$(cd "$(dirname "$0")/../.." && pwd)"; here="$repo/tests/shell"
command -v gnome-shell >/dev/null || { echo "SKIP: no gnome-shell"; exit 0; }
keep=${OUT:+1}; OUT="${OUT:-$(mktemp -d)}"; rc=0
shell_run() {  # shell_run NAME ACCENT_ENABLED : one headless Shell; probe writes NAME.txt / NAME.png
  local name=$1 on=$2 T; T=$(mktemp -d)
  ( export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_DATA_HOME=$T/home/.local/share XDG_CACHE_HOME=$T/home/.cache \
           XDG_RUNTIME_DIR=$T/run PROBE_OUT="$OUT/$name"
    mkdir -p "$XDG_DATA_HOME/gnome-shell/extensions" "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
    cp -r "$repo/modules/gnome-extensions/bundled/decal@decal" "$here/probe@decal" "$XDG_DATA_HOME/gnome-shell/extensions/"
    glib-compile-schemas "$XDG_DATA_HOME/gnome-shell/extensions/decal@decal/schemas"
    dbus-run-session -- bash -c '
      dconf write /org/gnome/shell/enabled-extensions "[\"decal@decal\", \"probe@decal\"]"
      dconf write /org/gnome/shell/welcome-dialog-last-shown-version "\"999\""
      dconf write /org/gnome/desktop/interface/accent-color "\"blue\""
      dconf write /org/gnome/shell/extensions/decal/accent-enabled '"$on"'
      gnome-shell --headless --wayland --no-x11 --virtual-monitor 1280x800 > "$PROBE_OUT.log" 2>&1 &
      for _ in $(seq 60); do [ -e "$PROBE_OUT.done" ] && break; sleep 1; done
      kill %1 2>/dev/null; wait 2>/dev/null' ) >/dev/null 2>&1
  # the document portal mounts $XDG_RUNTIME_DIR/doc and lingers a moment after the session ends
  for _ in 1 2 3 4 5; do fusermount3 -uz "$T/run/doc" 2>/dev/null || true; rm -rf "$T" 2>/dev/null && break; sleep 1; done
}
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; rc=1; fi; }
shell_run accent-off false
shell_run accent-on true
check "accent: shell started with the extension" '[[ -e $OUT/accent-on.done ]]'
check "accent: no JavaScript errors" '! grep -q "JS ERROR" "$OUT/accent-on.log" "$OUT/accent-off.log"'
check "accent: stylesheet loaded when on" 'grep -q "decal-accent" "$OUT/accent-on.txt"'
check "accent: nothing loaded when off" '! grep -q "decal-accent" "$OUT/accent-off.txt"'
check "accent: extension active" 'grep -q "\"state\":1" "$OUT/accent-on.txt"'
if [[ -n $keep ]]; then echo "screenshots: $OUT/accent-off.png $OUT/accent-on.png"; else rm -rf "$OUT"; fi
exit $rc
