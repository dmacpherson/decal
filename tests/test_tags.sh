#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# tags: [section.TAG] settings for machines given --tags TAG (lib/profile.py, the runner's --tags/--only)
M="$T_TMP/mods"; mkdir -p "$M"
for n in base list onlydev; do mkdir -p "$M/$n"; done
echo '{"keys": {"word": {"type": "string", "default": "hi"}, "size": {"type": "int", "default": 1}, "login.blur": {"type": "int", "default": 2}}}' > "$M/base/schema.json"
echo '{"keys": {"items": {"type": "strings", "default": []}, "keep": {"type": "strings", "default": []}}}' > "$M/list/schema.json"
echo '{"keys": {"on": {"type": "bool", "default": false}}}' > "$M/onlydev/schema.json"
for n in base onlydev; do cat > "$M/$n/module.sh" <<EOF
MODULE_DESC="tags fixture $n"
module_add()    { echo "$n add \${P_word:-} \${P_size:-} \${P_login_blur:-} \${P_on:-}" >> "\$LS_TEST_LOG"; }
module_remove() { echo "$n remove" >> "\$LS_TEST_LOG"; }
module_status() { echo not-installed; }
EOF
done
cat > "$M/list/module.sh" <<'EOF'
MODULE_DESC="tags fixture list"
MODULE_CAN_DROP=1
module_add()    { echo "list add ${P_items[*]}" >> "$LS_TEST_LOG"; }
module_drop()   { echo "list drop ${P_items[*]} keep=${P_keep[*]}" >> "$LS_TEST_LOG"; }
module_remove() { echo "list remove" >> "$LS_TEST_LOG"; }
module_status() { echo installed; }
EOF
export DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora DECAL_PROFILE="$T_TMP/p" LS_TEST_LOG="$T_TMP/log"
mkdir -p "$DECAL_PROFILE"; : > "$LS_TEST_LOG"
cat > "$DECAL_PROFILE/profile.toml" <<'EOF'
[base]
word = "plain"
[base.login]
blur = 5
[base.deck]
size = 9
[base.deck.login]
blur = 7

[list]
items = ["a", "b"]
keep = ["k"]
[list.dev]
items = ["b", "c", "d"]

[onlydev.dev]
on = true
EOF
S="$REPO/decal"
pv() { local m=$1 v=$2; shift 2; python3 "$REPO/lib/profile.py" shell "$m" --profile "$DECAL_PROFILE" --modules "$M" "$@" | grep -E "^declare -g[a]* $v=" | sed 's/^[^=]*=//'; }
log() { sed 's/ *$//; s/  */ /g' "$LS_TEST_LOG"; : > "$LS_TEST_LOG"; }

# the profile reader: merging
assert_eq "$(python3 "$REPO/lib/profile.py" check --profile "$DECAL_PROFILE" --modules "$M" 2>&1; echo $?)" "0" "a profile with tags is valid"
assert_eq "$(pv list P_items)" "(a b)" "no tags: only the untagged list"
assert_eq "$(DECAL_TAGS=dev pv list P_items)" "(a b c d)" "a tag's list adds on (no repeats)"
assert_eq "$(DECAL_TAGS=dev pv base P_word)" "plain" "a section without that tag: as it is"
assert_eq "$(DECAL_TAGS=deck pv base P_size)" "9" "a tag's value replaces"
assert_eq "$(DECAL_TAGS=deck pv base P_login_blur)" "7" "inside the module's own sub-tables too"
assert_eq "$(pv base P_login_blur)" "5" "[base.login] is the module's own table, not a tag"
assert_eq "$(DECAL_TAGS=all pv base P_size)" "9" "all = every tag"
assert_eq "$(DECAL_TAGS=all pv list P_items)" "(a b c d)" "all = every tag (lists)"
assert_eq "$(pv onlydev P__in_profile)" "false" "a section with only tag tables: not in the profile without the tag"
assert_eq "$(DECAL_TAGS=dev pv onlydev P__in_profile)" "true" "...and in it with the tag"
assert_eq "$(DECAL_TAGS=dev pv onlydev P_on)" "true" "...with the tag's settings"
assert_eq "$(python3 "$REPO/lib/profile.py" tags --profile "$DECAL_PROFILE" --modules "$M" | tr '\n' ' ')" "deck dev " "every tag in the profile, in file order"
assert_eq "$(pv list P_items --drop dev)" "(c d)" "drop: only what the tag adds to the lists"
assert_eq "$(pv list P_keep --drop dev)" "()" "drop: lists the tag doesn't touch are empty"
chk() { python3 "$REPO/lib/profile.py" check --profile "$T_TMP/bad" --modules "$M" 2>&1; }
mkdir -p "$T_TMP/bad"
printf '[list.all]\nitems = ["x"]\n' > "$T_TMP/bad/profile.toml"
assert_contains "$(chk)" "'all' is not a tag name" "all is reserved"
printf '[list.dev]\nitem = ["x"]\n' > "$T_TMP/bad/profile.toml"
assert_contains "$(chk)" "[list.dev] unknown key 'item'" "a tag's settings are checked like the section's"
printf '[base.deck]\nsize = "big"\n' > "$T_TMP/bad/profile.toml"
assert_contains "$(chk)" "[base.deck] size: expected an integer" "and their values too"

# the runner
"$S" add all >/dev/null 2>&1
assert_eq "$(log)" "base add plain 1 5
list add a b" "add all: the untagged settings only, tag-only modules left out"
"$S" add all --tags dev >/dev/null 2>&1
assert_eq "$(log)" "base add plain 1 5
list add a b c d
onlydev add true" "--tags dev: dev's settings and modules too"
"$S" --tags all add base >/dev/null 2>&1
assert_eq "$(log)" "base add plain 9 7" "--tags all on one module: every tag"
: > "$LS_TEST_LOG"; out=$("$S" add onlydev --force 2>&1); assert_eq "$?" "0" "a tag-only module named on its own: added"
assert_eq "$(log)" "onlydev add true" "...with its tag's settings, and nothing else of the tag (list untouched)"
assert_contains "$out" "onlydev: using its [onlydev.dev] settings" "...and says so"
out=$("$S" add all --tags dvel 2>&1); assert_eq "$?" "1" "an unknown tag: refused"
assert_contains "$out" "no section of the profile has the tag 'dvel' (tags in the profile: deck, dev)" "and lists the real ones"
: > "$LS_TEST_LOG"
"$S" add all --only dev --force >/dev/null 2>&1
assert_eq "$(log)" "list add a b c d
onlydev add true" "--only dev: just the modules with a dev section"
out=$("$S" add base --only dev 2>&1)
assert_contains "$out" "base has no [base.dev] section: skipped" "--only on a module without the tag: says so"
assert_eq "$(log)" "" "...and runs nothing"
out=$("$S" status 2>&1)
assert_contains "$out" "onlydev            not in profile (tags: dev)" "status: a tag-only module names its tag"
out=$("$S" status --tags dev 2>&1)
assert_not_contains "$out" "onlydev            not in profile" "status --tags dev: in the profile"
out=$("$S" tags 2>&1)
assert_contains "$out" "deck         base" "tags: which sections have each tag"
assert_contains "$out" "dev          list onlydev" "tags: dev"
: > "$LS_TEST_LOG"
"$S" remove all --only dev >/dev/null 2>&1
assert_eq "$(log)" "onlydev remove
list drop c d keep=" "remove --only dev: a module only there through dev goes; one there anyway loses dev's additions"
sed -i 's/^MODULE_CAN_DROP=1$//' "$M/list/module.sh"
out=$("$S" remove list --only dev 2>&1)
assert_contains "$out" "list: what dev adds to it is left in place" "a module that can't take part of itself away: left, with a warning"
assert_eq "$(log)" "" "...and not removed"
"$S" remove all >/dev/null 2>&1
assert_eq "$(log)" "onlydev remove
list remove
base remove" "remove all without --only: unchanged"
t_done
