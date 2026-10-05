#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora
# a Flatpak Brave profile with settings of its own; the profile's file sets a few, one of them inside a bigger object
B="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"; mkdir -p "$B"
echo '{"brave":{"new_tab_page":{"show_clock":false},"other":1},"profile":{"name":"Personal"},"default_search_provider_data":{"template_url_data":{"short_name":"Brave","usage_count":9}}}' > "$B/Preferences"
echo '{"brave":{"new_tab_page":{"show_clock":true,"show_stats":false}},"default_search_provider_data":{"template_url_data":{"short_name":"DuckDuckGo"}}}' > "$PROFILE_DIR/brave.json"
# Local State (browser-wide): Brave Origin
L="$(dirname "$B")/Local State"; echo '{"brave":{"origin":{"free_tier_accepted":false}},"browser":{"x":1}}' > "$L"
echo '{"brave":{"origin":{"free_tier_accepted":true,"purchase_validated":true}}}' > "$PROFILE_DIR/brave-ls.json"
printf '[brave]\npreferences = "brave.json"\nlocal-state = "brave-ls.json"\n' >> "$PROFILE_DIR/profile.toml"
stub flatpak 'case "$*" in ps*) if [ -e "$STUBS/running" ]; then echo com.brave.Browser; fi;; esac; exit 0'; stub pgrep 'exit 1'
run_mod() { mod_run brave "module_$1"; }
q() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d.get(k) if isinstance(d, dict) else None
print(json.dumps(d))' "${2:-$B/Preferences}" "$1"; }

assert_eq "$(run_mod status)" "not-installed" "before"
# Brave rewrites its settings when it closes: nothing is written while it runs
touch "$STUBS/running"; out=$(run_mod add 2>&1); assert_eq "$?" "0" "add while Brave runs: no failure"
assert_contains "$out" "close Brave" "says to close Brave"; assert_eq "$(q brave.new_tab_page.show_clock)" "false" "nothing written while it runs"
assert_eq "$(run_mod status)" "partial (close Brave to apply)" "status while it runs"
rm "$STUBS/running"; run_mod add >/dev/null 2>&1
assert_eq "$(q brave.new_tab_page.show_clock)" "true" "setting applied"; assert_eq "$(q brave.new_tab_page.show_stats)" "false" "new setting added"
assert_eq "$(q default_search_provider_data.template_url_data.short_name)" '"DuckDuckGo"' "value inside a bigger object applied"
assert_eq "$(q default_search_provider_data.template_url_data.usage_count)" "9" "the rest of that object kept"
assert_eq "$(q profile.name)" '"Personal"' "unrelated settings kept"; assert_eq "$(q brave.other)" "1" "siblings kept"
assert_eq "$(q brave.origin.free_tier_accepted "$L")" "true" "Brave Origin switched on in Local State"
assert_eq "$(q brave.origin.purchase_validated "$L")" "true" "(both flags Brave's own button sets)"; assert_eq "$(q browser.x "$L")" "1" "rest of Local State kept"
assert_eq "$(run_mod status)" "installed" "status after add"
# changed in Brave afterwards: shows up, re-applied; remove still restores what was there before decal
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["brave"]["new_tab_page"]["show_clock"]=False; json.dump(d,open(p,"w"))' "$B/Preferences"
assert_eq "$(run_mod status)" "not-installed" "changed in Brave: status says so"
run_mod add >/dev/null 2>&1; assert_eq "$(q brave.new_tab_page.show_clock)" "true" "re-applied"
run_mod remove >/dev/null 2>&1
assert_eq "$(q brave.new_tab_page.show_clock)" "false" "remove restores the value from before decal"
assert_eq "$(q brave.new_tab_page.show_stats)" "null" "a setting decal added is taken out again"
assert_eq "$(q default_search_provider_data.template_url_data.short_name)" '"Brave"' "search engine restored"
assert_eq "$(q brave.origin.free_tier_accepted "$L")" "false" "Origin back to how it was"
assert_eq "$(q brave.origin.purchase_validated "$L")" "null" "flag decal added taken out"
assert_nofile "$DECAL_USER_STATE/brave.prev.json" "record removed"
# extensions: a file each in Brave's "External Extensions" folder; Brave installs them from the Web Store on its next start
X="$(dirname "$B")/External Extensions"; A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; C=cccccccccccccccccccccccccccccccc
printf 'extensions = ["%s", "not-an-id"]\n[brave.me]\nextensions = ["%s"]\n' "$A" "$C" >> "$PROFILE_DIR/profile.toml"
touch "$STUBS/running"; out=$(run_mod add 2>&1)
assert_eq "$(cat "$X/$A.json")" '{"external_update_url": "https://clients2.google.com/service/update2/crx"}' "extension added (even while Brave runs)"
assert_contains "$out" "not-an-id is not a Chrome Web Store extension id" "a bad id: warned"; rm "$STUBS/running"
assert_nofile "$X/$C.json" "a tag's extension: not without the tag"
DECAL_TAGS=me run_mod add >/dev/null 2>&1; assert_file "$X/$C.json" "with the tag: added"
echo '{"external_update_url": "mine"}' > "$X/mine.json"
DECAL_DROP=me run_mod drop >/dev/null 2>&1
assert_nofile "$X/$C.json" "remove --only me: the tag's extension taken out (Brave uninstalls it)"; assert_file "$X/$A.json" "the section's kept"
rm "$X/$A.json"; assert_eq "$(run_mod status)" "partial (extensions not added)" "a missing extension shows up"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_nofile "$X/$A.json" "remove takes decal's extensions out"; assert_file "$X/mine.json" "never one decal didn't add"
sed -i '/^extensions = /d; /^\[brave.me\]/d' "$PROFILE_DIR/profile.toml"
# Brave never opened: nothing to merge into yet
rm -rf "$B"; out=$(run_mod add 2>&1); assert_eq "$?" "0" "never-opened Brave: no failure"
assert_contains "$out" "open it once" "says to open Brave once"
# undo goes to the browser profile decal changed, even after [brave] profile changes or the section is gone (audit batch 2)
run_mod remove >/dev/null 2>&1
P1="$(dirname "$B")/Profile 1"; mkdir -p "$P1"; echo '{"brave":{"new_tab_page":{"show_clock":false}}}' > "$P1/Preferences"
sed -i 's/^\[brave\]$/&\nprofile = "Profile 1"/' "$PROFILE_DIR/profile.toml"; run_mod add >/dev/null 2>&1
assert_eq "$(q brave.new_tab_page.show_clock "$P1/Preferences")" "true" "applied to Profile 1"
cp "$B/Preferences" "$T_TMP/default-before"
sed -i '/^profile = "Profile 1"$/d' "$PROFILE_DIR/profile.toml"; run_mod remove >/dev/null 2>&1
assert_eq "$(q brave.new_tab_page.show_clock "$P1/Preferences")" "false" "undo restored Profile 1 (the one decal changed)"
assert_eq "$(cat "$B/Preferences")" "$(cat "$T_TMP/default-before")" "...and left Default alone"
t_done
