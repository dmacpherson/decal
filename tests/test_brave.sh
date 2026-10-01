#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora
# a Flatpak Brave profile with settings of its own; the profile's file sets a few, one of them inside a bigger object
B="$HOME/.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default"; mkdir -p "$B"
echo '{"brave":{"new_tab_page":{"show_clock":false},"other":1},"profile":{"name":"Personal"},"default_search_provider_data":{"template_url_data":{"short_name":"Brave","usage_count":9}}}' > "$B/Preferences"
echo '{"brave":{"new_tab_page":{"show_clock":true,"show_stats":false}},"default_search_provider_data":{"template_url_data":{"short_name":"DuckDuckGo"}}}' > "$PROFILE_DIR/brave.json"
printf '[brave]\npreferences = "brave.json"\n' >> "$PROFILE_DIR/profile.toml"
stub flatpak 'case "$*" in ps*) if [ -e "$STUBS/running" ]; then echo com.brave.Browser; fi;; esac; exit 0'; stub pgrep 'exit 1'
run_mod() { mod_run brave "module_$1"; }
q() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d.get(k) if isinstance(d, dict) else None
print(json.dumps(d))' "$B/Preferences" "$1"; }

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
assert_eq "$(run_mod status)" "installed" "status after add"
# changed in Brave afterwards: shows up, re-applied; remove still restores what was there before decal
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["brave"]["new_tab_page"]["show_clock"]=False; json.dump(d,open(p,"w"))' "$B/Preferences"
assert_eq "$(run_mod status)" "not-installed" "changed in Brave: status says so"
run_mod add >/dev/null 2>&1; assert_eq "$(q brave.new_tab_page.show_clock)" "true" "re-applied"
run_mod remove >/dev/null 2>&1
assert_eq "$(q brave.new_tab_page.show_clock)" "false" "remove restores the value from before decal"
assert_eq "$(q brave.new_tab_page.show_stats)" "null" "a setting decal added is taken out again"
assert_eq "$(q default_search_provider_data.template_url_data.short_name)" '"Brave"' "search engine restored"
assert_nofile "$DECAL_USER_STATE/brave.prev.json" "record removed"
# Brave never opened: nothing to merge into yet
rm -rf "$B"; out=$(run_mod add 2>&1); assert_eq "$?" "0" "never-opened Brave: no failure"
assert_contains "$out" "open it once" "says to open Brave once"
t_done
