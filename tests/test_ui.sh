#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# the menu (lib/ui.py): what each action runs, then whole flows typed into it in a pseudo-terminal
py() { python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import ui; print($1)"; }
assert_eq "$(py 'ui.apply_cmds(["dev"], ["a", "b"], ["a", "b"])')" "[['--tags', 'dev', 'add', 'all']]" "apply: everything ticked -> add all"
assert_eq "$(py 'ui.apply_cmds([], ["a"], ["a", "b"])')" "[['add', 'a']]" "apply: some modules, no tags"
assert_eq "$(py 'ui.stamp_cmd(["a"], False, "/x.tgz", "me/r", True)')" "['stamp', 'a', '/x.tgz', '-gh', 'me/r', '--public']" "stamp: modules, path, GitHub, public"
assert_eq "$(py 'ui.stamp_cmd(["a", "b"], True, gh="")')" "['stamp', '-gh']" "stamp: everything, default repo"
assert_eq "$(py 'ui.remove_cmds(["dev"], ["a"])')" "[['remove', 'all', '--only', 'dev'], ['remove', 'a']]" "remove: a tag, then modules"

# fixture modules: one everywhere, one only with the dev tag; status follows what was added
M="$T_TMP/mods"; mkdir -p "$M"
for n in base onlydev; do mkdir -p "$M/$n"; echo '{"keys": {"on": {"type": "bool", "default": true}}}' > "$M/$n/schema.json"
  cat > "$M/$n/module.sh" <<MOD
MODULE_DESC="ui fixture $n"
module_add()    { [[ \$LS_DRY_RUN == 1 ]] && return 0; echo "$n add" >> "\$LS_TEST_LOG"; touch "\$T_TMP/$n.on"; }
module_remove() { [[ \$LS_DRY_RUN == 1 ]] && return 0; echo "$n remove" >> "\$LS_TEST_LOG"; rm -f "\$T_TMP/$n.on"; }
module_status() { if [[ -e \$T_TMP/$n.on ]]; then echo installed; else echo not-installed; fi; }
MOD
done
P="$T_TMP/prof"; mkdir -p "$P"; printf '[base]\non = true\n[onlydev.dev]\non = true\n' > "$P/profile.toml"
export T_TMP DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora DECAL_PROFILE="$P" LS_TEST_LOG="$T_TMP/log"; : > "$LS_TEST_LOG"
D() { python3 "$REPO/tests/fixtures/drive_ui.py" "$T_TMP/screen" "$@"; }

D "$REPO/decal" ui -- q; assert_eq "$?" "0" "menu opens, q quits"
S=$(cat "$T_TMP/screen")
assert_contains "$S" "Apply" "menu: Apply"; assert_contains "$S" "stick it on" "...with its sticker name"
assert_contains "$S" "Remove" "menu: Remove (a profile is active)"; assert_not_contains "$S" "Update" "no Update unless a newer version is out"
# apply: the active profile, tick the dev tag (brings its module), preview, apply, back, quit
D "$REPO/decal" ui -- 1 ENTER SPACE ENTER WAIT ENTER WAIT ENTER q; assert_eq "$?" "0" "apply flow rc"
assert_contains "$(cat "$T_TMP/screen")" "--tags dev add all" "apply: the command it runs is shown"
assert_eq "$(sort "$LS_TEST_LOG" | tr '\n' ' ')" "base add onlydev add " "apply: both modules added (dev ticked)"
assert_contains "$(cat "$T_TMP/screen")" "Stuck on: 2 modules" "apply: the sticker-flavoured result"
assert_eq "$(cat "$DECAL_USER_STATE/tags")" "dev" "the tags used are remembered"
D "$REPO/decal" ui -- 1 ENTER q; assert_contains "$(cat "$T_TMP/screen")" "[x] tag: dev" "...and pre-ticked next time"
# remove: tick the dev tag, preview, confirm by typing remove
: > "$LS_TEST_LOG"
D "$REPO/decal" ui -- 3 SPACE ENTER WAIT ENTER r e m o v e ENTER WAIT ENTER q
assert_eq "$(cat "$LS_TEST_LOG")" "onlydev remove" "remove: the dev tag's module peeled off, the rest kept"
assert_contains "$(cat "$T_TMP/screen")" "Peeled off: tag dev" "remove: the result"
: > "$LS_TEST_LOG"
D "$REPO/decal" ui -- 3 DOWN DOWN SPACE ENTER WAIT ENTER n o p e ENTER q
assert_eq "$(cat "$LS_TEST_LOG")" "" "remove: anything but \"remove\" typed cancels it"
# no profile yet: only Apply, Stamp, Logs, and a line saying what to do
DECAL_PROFILE="$T_TMP/none" D "$REPO/decal" ui -- q; S=$(cat "$T_TMP/screen")
assert_contains "$S" "No profile yet" "no profile: says so"; assert_not_contains "$S" "Remove" "no profile: no Remove"
# bare decal: the menu in a terminal, the usage otherwise
D "$REPO/decal" -- q; assert_contains "$(cat "$T_TMP/screen")" "stick it on" "bare decal in a terminal: the menu"
out=$("$REPO/decal" 2>&1 < /dev/null); assert_eq "$?" "1" "bare decal without a terminal: usage"; assert_contains "$out" "usage:" "...the usage text"
t_done
