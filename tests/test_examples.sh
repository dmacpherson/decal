#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
out=$(python3 "$REPO/lib/profile.py" check --profile "$REPO/examples/profile" --modules "$REPO/modules" 2>&1)
assert_eq "$out" "" "example profile is valid"
secs=$(python3 "$REPO/lib/profile.py" sections --profile "$REPO/examples/profile" --modules "$REPO/modules" | tr '\n' ' ')
assert_eq "$secs" "apps branding cursor gtk-theme icons plymouth terminal " "example covers the modules that need no personal files"
# no module ships personal data any more
for f in modules/wallpaper/wallpaper.jpg modules/apps/apps.list modules/apps/defaults.list modules/gnome-settings/settings.ini \
         modules/gnome-extensions/settings.ini modules/gnome-extensions/extensions.list modules/terminal/config.sh modules/plymouth/themes; do
  assert_nofile "$REPO/$f" "no personal/vendored data: $f"
done
for m in "$REPO"/modules/*/; do assert_file "$m/schema.json" "schema for $(basename "$m")"; done
t_done
