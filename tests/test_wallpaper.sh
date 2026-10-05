#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
W="$REPO/modules/wallpaper"
# gdm-background refuses to mount when the stock file changed (GNOME update)
st="$DECAL_STATE/wallpaper"; mkdir -p "$st"
echo stock > "$T_TMP/stock.gresource"; echo built > "$st/gnome-shell-theme.gresource"
echo "$T_TMP/stock.gresource" > "$st/stock-path"; echo "0000deadbeef" > "$st/stock.sha256"
stub mount; stub findmnt 'exit 1'; stub chcon; stub selinuxenabled 'exit 1'
out=$(bash "$W/gdm-background" mount 2>&1); assert_eq "$?" "0" "stale exits 0"
assert_contains "$out" "stock theme changed" "stale message"; assert_not_contains "$(calls)" "mount --bind" "no mount when stale"
assert_eq "$(cat "$st/state")" "stale" "boot helper records stale for status"
# matching hash -> mounts
sha256sum "$T_TMP/stock.gresource" | cut -d' ' -f1 > "$st/stock.sha256"; : > "$STUBS/calls"
bash "$W/gdm-background" mount; assert_contains "$(calls)" "mount --bind $st/gnome-shell-theme.gresource $T_TMP/stock.gresource" "mounts when matching"
assert_eq "$(cat "$st/state")" "mounted" "records mounted"
# stock-copy returns the real stock bytes (not mounted here -> direct copy)
bash "$W/gdm-background" stock-copy "$T_TMP/stock.gresource" "$T_TMP/copy.gresource"
assert_eq "$(cat "$T_TMP/copy.gresource")" "stock" "stock-copy"
# while something is mounted over the stock path, stock-copy reads underneath via a bind of the parent dir
stub findmnt 'exit 0'; : > "$STUBS/calls"
bash "$W/gdm-background" stock-copy "$T_TMP/stock.gresource" "$T_TMP/copy2.gresource" 2>/dev/null
assert_contains "$(calls)" "mount --bind $T_TMP " "reads underneath an active mount"
stub findmnt 'exit 1'
# status reads the helper's state (no root, no hashing of a covered file)
echo stale > "$st/state"
out=$( ( stub systemctl 'exit 0'; stub gsettings 'exit 0'; DECAL_PLATFORM=fedora mod_run wallpaper module_status ) 2>/dev/null)
assert_contains "$out" "stale" "status shows stale from boot helper"
# extract.py refuses an already-patched theme (e.g. read through an active mount)
if [[ -r /var/lib/decal/gdm/gnome-shell-theme.gresource ]]; then
  out=$(python3 "$W/extract.py" /var/lib/decal/gdm/gnome-shell-theme.gresource "$T_TMP/src2" 2>&1); rc=$?
  assert_eq "$rc" "1" "patched input refused"; assert_contains "$out" "already contains" "refusal message"
fi
# extract.py against the REAL stock gresource keeps every entry and adds rule + image entry
STOCK=/usr/share/gnome-shell/gnome-shell-theme.gresource
if /usr/bin/findmnt -rn "$STOCK" >/dev/null 2>&1 && command -v rpm-ostree >/dev/null; then   # covered by a mount: use the booted deployment's copy
  STOCK=$(rpm-ostree status --json | python3 -c 'import json,sys; d=[x for x in json.load(sys.stdin)["deployments"] if x["booted"]][0]; print("/ostree/deploy/%s/deploy/%s.%s" % (d["osname"],d["checksum"],d["serial"]))')/usr/share/gnome-shell/gnome-shell-theme.gresource
fi
python3 "$W/extract.py" "$STOCK" "$T_TMP/src"
assert_contains "$(cat "$T_TMP/src/gnome-shell-dark.css")" "decal-background.jpg" "rule in dark css"
assert_contains "$(cat "$T_TMP/src/gnome-shell-light.css")" "decal-background.jpg" "rule in light css"
assert_contains "$(cat "$T_TMP/src/gnome-shell-theme.gresource.xml")" "<file>decal-background.jpg</file>" "xml entry"
assert_contains "$(cat "$T_TMP/src/gnome-shell-theme.gresource.xml")" "<file>pad-osd.css</file>" "stock entries kept"
# monitors.py canvas math from a fixed layout (2x 3840x2160 @1.25, side by side) -> 7680x2160
out=$(python3 "$W/monitors.py" --from-json '[{"x":0,"y":0,"w":3840,"h":2160,"scale":1.25},{"x":3072,"y":0,"w":3840,"h":2160,"scale":1.25}]')
assert_eq "$out" '{"width": 7680, "height": 2160, "rects": [[0, 0, 3840, 2160], [3840, 0, 3840, 2160]]}' "canvas math"
# a failed SELinux relabel must not mount a mislabelled theme (GDM could fail to read it)
st="$DECAL_STATE/wallpaper"; mkdir -p "$st"; echo stock > "$T_TMP/stock.gresource"; echo built > "$st/gnome-shell-theme.gresource"
echo "$T_TMP/stock.gresource" > "$st/stock-path"; sha256sum "$T_TMP/stock.gresource" | cut -d' ' -f1 > "$st/stock.sha256"
stub selinuxenabled 'exit 0'; stub chcon 'exit 1'; stub findmnt 'exit 1'; : > "$STUBS/calls"
bash "$W/gdm-background" mount 2>/dev/null
assert_not_contains "$(calls)" "mount --bind $st/gnome-shell-theme.gresource" "no mount when relabel fails"
assert_eq "$(cat "$st/state")" "label-failed" "records label failure"
stub selinuxenabled 'exit 1'; rm -rf "$st"
# add (dry-run): login part only on fedora-atomic; monitor layout goes to /etc/xdg/monitors.xml
mkdir -p "$T_TMP/h/.config"; echo '<monitors/>' > "$T_TMP/h/.config/monitors.xml"; stub gdm; stub gsettings 'exit 0'
export DECAL_MONITORS_JSON='{"width": 3840, "height": 2160, "rects": [[0, 0, 3840, 2160]]}'
wp_add() { ( export HOME="$T_TMP/h" LS_DRY_RUN=1 DECAL_PLATFORM=$1; mod_run wallpaper module_add ) 2>&1; }
out=$(wp_add fedora-atomic); assert_contains "$out" "GNOME Shell theme not found" "missing stock theme: clear warning, no silent exit"
mkdir -p "$DECAL_ROOT/usr/share/gnome-shell"; echo stock > "$DECAL_ROOT/usr/share/gnome-shell/gnome-shell-theme.gresource"
out=$(wp_add fedora-atomic)
assert_contains "$out" "write $DECAL_ROOT/etc/xdg/monitors.xml" "monitor layout -> /etc/xdg (GDM dynamic greeter users read it)"
assert_not_contains "$out" "/var/lib/gdm/.config" "never the static gdm home"
assert_contains "$out" "decal-gdm-background.service" "atomic: login part runs"
stub dnf5; stub rpm 'exit 0'   # a dnf5 Fedora where the actions plugin is already installed
out=$(wp_add fedora)
assert_contains "$out" "decal-wallpaper.actions" "fedora: dnf5 actions hook written"
assert_contains "$out" "decal-gdm-background.service" "mutable: login part now runs"
out=$(DECAL_NO_DNF5=1 wp_add fedora)
assert_contains "$out" "login background skipped" "dnf4-only: skipped with a reason"
assert_not_contains "$out" "decal-gdm-background.service" "dnf4-only: no mount unit"
unset DECAL_MONITORS_JSON
# remove on a machine where it was never added runs nothing privileged
rm -rf "$DECAL_STATE"; stub gsettings 'exit 0'; stub getent 'echo gdm:x:42:42::/var/lib/gdm:/sbin/nologin'; : > "$STUBS/calls"
( DECAL_PLATFORM=fedora-atomic mod_run wallpaper module_remove ) 2>/dev/null
assert_not_contains "$(calls)" "systemctl" "remove never-added: no systemctl"; assert_not_contains "$(calls)" "rm -rf" "remove never-added: no rm -rf"
# per-target images and settings (dry-run shows exactly what would be built)
export DECAL_MONITORS_JSON='{"width": 3840, "height": 2160, "rects": [[0, 0, 3840, 2160]]}'
out=$(wp_add fedora-atomic)
assert_contains "$out" "build.sh $PROFILE_DIR/wallpaper.jpg 24 65" "login defaults: blur 24, brightness 65"
assert_contains "$out" "cp $PROFILE_DIR/wallpaper.jpg" "desktop defaults: sharp copy"
cp "$PROFILE_DIR/wallpaper.jpg" "$PROFILE_DIR/login.jpg"
printf '[wallpaper.login]\nimage = "login.jpg"\nblur = 40\n[wallpaper.desktop]\nblur = 10\nbrightness = 80\n' >> "$PROFILE_DIR/profile.toml"
out=$(wp_add fedora-atomic)
assert_contains "$out" "build.sh $PROFILE_DIR/login.jpg 40 65" "login.image + login.blur override"
assert_contains "$out" "desktop.sh $PROFILE_DIR/wallpaper.jpg 10 80" "desktop processed with its own settings"
python3 - "$PROFILE_DIR/profile.toml" <<'EOF'
import sys; p=sys.argv[1]; s=open(p).read(); s=s.replace('image = "wallpaper.jpg"\n','',1); open(p,'w').write(s)
EOF
sed -i '/^\[wallpaper.desktop\]/,$d' "$PROFILE_DIR/profile.toml"
out=$(wp_add fedora-atomic); assert_contains "$out" "[wallpaper] needs 'image'" "desktop without any image: clear error"
# both images are resolved (downloaded) before anything on the system changes
printf '[wallpaper]\nimage = "https://example.invalid/w.jpg"\n[wallpaper.desktop]\nimage = "https://example.invalid/d.jpg"\n' > "$T_TMP/wp.toml"
python3 - "$PROFILE_DIR/profile.toml" "$T_TMP/wp.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[wallpaper(\.[a-z]+)?\]\n.*?(?=^\[(?!wallpaper)|\Z)","",s); open(p,'w').write(s+open(sys.argv[2]).read())
EOF
stub dnf5; stub rpm 'exit 0'
out=$(wp_add fedora)
first_change=$(grep -n 'decal-wallpaper.actions\|write \|systemctl' <<<"$out" | head -1 | cut -d: -f1)
last_fetch=$(grep -n 'fetch https://example.invalid' <<<"$out" | tail -1 | cut -d: -f1)
assert_eq "$(grep -c 'fetch https://example.invalid' <<<"$out")" "2" "both images fetched"
assert_eq "$(( last_fetch < first_change ))" "1" "images fetched before any change"
unset DECAL_MONITORS_JSON
# switching a part off undoes it on the next add
mkdir -p "$DECAL_USER_STATE"; printf "picture-uri='file:///old.jpg'\npicture-uri-dark='file:///old.jpg'\n" > "$DECAL_USER_STATE/wallpaper.prev"
mkdir -p "$DECAL_ROOT/etc/systemd/system"; : > "$DECAL_ROOT/etc/systemd/system/decal-gdm-background.service"
printf '[wallpaper.login]\nenable = false\n' >> "$T_TMP/wp.toml"; sed -i 's/^\[wallpaper.desktop\]$/&\nenable = false/' "$T_TMP/wp.toml"
python3 - "$PROFILE_DIR/profile.toml" "$T_TMP/wp.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[wallpaper(\.[a-z]+)?\]\n.*?(?=^\[(?!wallpaper)|\Z)","",s); open(p,'w').write(s+open(sys.argv[2]).read())
EOF
out=$(wp_add fedora)
assert_contains "$out" "gsettings set org.gnome.desktop.background picture-uri 'file:///old.jpg'" "desktop.enable = false restores the previous wallpaper"
assert_contains "$out" "systemctl disable --now decal-gdm-background.service" "login.enable = false removes the login background"
assert_not_contains "$out" "fetch https://example.invalid" "nothing fetched for disabled parts"
rm -f "$DECAL_ROOT/etc/systemd/system/decal-gdm-background.service" "$DECAL_USER_STATE/wallpaper.prev"
# remove also removes the package the hooks needed (dnf5 actions plugin)
mkdir -p "$DECAL_STATE/pkgs"; echo libdnf5-plugin-actions > "$DECAL_STATE/pkgs/wallpaper"; stub dnf; : > "$STUBS/calls"
( DECAL_PLATFORM=fedora mod_run wallpaper module_remove ) >/dev/null 2>&1
assert_contains "$(calls)" "dnf remove -y -- libdnf5-plugin-actions" "hooks package removed with the module"
t_done
