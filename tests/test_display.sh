#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora DECAL_DISPLAY_FAKE="$T_TMP/display.json"
H="$REPO/modules/display/scale.py"
# two 4K screens side by side at 200% (GNOME's own pick), the right one primary... left one primary
state() { cat > "$DECAL_DISPLAY_FAKE" <<EOS
{"serial": 7, "layout_mode": 1,
 "monitors": {"DP-1": {"mode": "3840x2160@60", "w": 3840, "h": 2160, "scales": [1.0, 1.25, 1.3333333730697632, 1.5, 1.6666666269302368, 2.0]},
              "DP-2": {"mode": "3840x2160@60", "w": 3840, "h": 2160, "scales": [1.0, 1.25, 1.3333333730697632, 1.5, 1.6666666269302368, 2.0]}},
 "logical": [$1]}
EOS
}
state '{"x": 0, "y": 0, "scale": 2.0, "transform": 0, "primary": true, "monitors": ["DP-1"]}, {"x": 1920, "y": 0, "scale": 2.0, "transform": 0, "primary": false, "monitors": ["DP-2"]}'
lay() { python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print(" ".join("%s@%s,%sx%s" % (m["monitors"][0], m["x"], m["y"], m["scale"]) for m in c["logical"]))' "$1"; }
python3 "$H" plan "$DECAL_DISPLAY_FAKE" 1.5 > "$T_TMP/p.json"
assert_eq "$(lay "$T_TMP/p.json")" "DP-1@0,0x1.5 DP-2@2560,0x1.5" "side by side: positions follow the new size"
# stacked screens stay stacked
state '{"x": 0, "y": 0, "scale": 1.0, "transform": 0, "primary": true, "monitors": ["DP-1"]}, {"x": 0, "y": 2160, "scale": 1.0, "transform": 0, "primary": false, "monitors": ["DP-2"]}'
python3 "$H" plan "$DECAL_DISPLAY_FAKE" 1.5 > "$T_TMP/p.json"
assert_eq "$(lay "$T_TMP/p.json")" "DP-1@0,0x1.5 DP-2@0,1440x1.5" "stacked: stays stacked"
# a scale the screen can't do: the closest supported one
python3 "$H" plan "$DECAL_DISPLAY_FAKE" 1.4 > "$T_TMP/p.json" 2>"$T_TMP/err"
assert_contains "$(lay "$T_TMP/p.json")" "x1.3333" "unsupported scale: closest supported one"
assert_contains "$(cat "$T_TMP/err")" "1.4" "and says so"
# the module: applies, records what was there, does nothing when already set, remove restores
state '{"x": 0, "y": 0, "scale": 2.0, "transform": 0, "primary": true, "monitors": ["DP-1"]}, {"x": 1920, "y": 0, "scale": 2.0, "transform": 0, "primary": false, "monitors": ["DP-2"]}'
printf '[display]\nscale = 1.5\n' >> "$PROFILE_DIR/profile.toml"
run_mod() { mod_run display "module_$1"; }
run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "add rc"
assert_eq "$(lay "$DECAL_DISPLAY_FAKE.applied")" "DP-1@0,0x1.5 DP-2@2560,0x1.5" "applied"
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["persistent"])' "$DECAL_DISPLAY_FAKE.applied")" "True" "saved like Settings does (persistent)"
cp "$DECAL_DISPLAY_FAKE.applied" "$T_TMP/a1"; python3 -c 'import json,sys
s=json.load(open(sys.argv[1])); a=json.load(open(sys.argv[2])); s["logical"]=a["logical"]; json.dump(s,open(sys.argv[1],"w"))' "$DECAL_DISPLAY_FAKE" "$T_TMP/a1"
rm -f "$DECAL_DISPLAY_FAKE.applied"; run_mod add >/dev/null 2>&1
assert_nofile "$DECAL_DISPLAY_FAKE.applied" "already at the scale: nothing applied"
assert_eq "$(run_mod status 2>/dev/null)" "installed" "status"
run_mod remove >/dev/null 2>&1
assert_eq "$(lay "$DECAL_DISPLAY_FAKE.applied")" "DP-1@0,0x2.0 DP-2@1920,0x2.0" "remove puts the previous layout back"
# no GNOME display service (e.g. not in a GNOME session): skipped, not an error
DECAL_DISPLAY_FAKE="$T_TMP/none.json" run_mod add >/dev/null 2>&1; assert_eq "$?" "0" "no display service: skipped"
# taken out of the profile (scaling differs per machine): status doesn't compare against an empty scale
sed -i '/^\[display\]/,$d' "$PROFILE_DIR/profile.toml"
assert_eq "$(run_mod status 2>/dev/null)" "not-installed" "not in the profile, never set: not-installed"
mkdir -p "$DECAL_USER_STATE"; echo '{}' > "$DECAL_USER_STATE/display.prev"
assert_eq "$(run_mod status 2>/dev/null)" "installed" "not in the profile, set earlier: installed (remove can undo it)"
t_done
