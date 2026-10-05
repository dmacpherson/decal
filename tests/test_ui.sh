#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'; export DECAL_MEDIA="$T_TMP/media"; mkdir -p "$DECAL_MEDIA"
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
D() {  # D CMD... -- KEYS: drive the menu, starting once its main screen is up (keys sent while it loads can be lost)
  local cmd=() ; while [[ $1 != -- ]]; do cmd+=("$1"); shift; done; shift
  python3 "$REPO/tests/fixtures/drive_ui.py" "$T_TMP/screen" "${cmd[@]}" -- "UNTIL:q quit" "$@"; }

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
# the browser: groups, the active row, sign-in row, new and enter; pure layout
rows() { python3 -c "import sys,json; sys.path.insert(0, '$REPO/lib'); import ui
d = json.loads(sys.argv[1]); [print(s, '|', l, '|', a) for s, l, a, v in ui.browser_rows(d, sys.argv[2], 'me')]" "$1" "$2"; }
D1='{"entries": [{"kind": "file", "source": "/h/decal-me.tar.gz", "name": "~/decal-me.tar.gz", "updated": "2026-10-01T00:00:00+00:00", "modules": 3, "active": true},
 {"kind": "recent", "source": "github:friend/setup", "name": "friend/setup", "updated": "2026-10-01T00:00:00+00:00", "active": false}],
 "notes": [], "signed_in": false, "active": "/h/decal-me.tar.gz"}'
R=$(rows "$D1" apply)
assert_contains "$R" "head | On GitHub |" "browser: GitHub group"
assert_contains "$R" "row | Sign in to see your GitHub profiles |" "browser: no key → sign-in row"
assert_contains "$R" "row | ~/decal-me.tar.gz | file · " "browser: a local stamp"
assert_contains "$R" "← active" "browser: the active mark"
assert_contains "$R" "head | Recently used |" "apply: recently used shown"
assert_contains "$R" "row | + Make a new profile |" "browser: new"
assert_contains "$R" "row | › Enter a profile… | a link, owner/name, a file or a folder" "browser: enter"
R=$(rows "$D1" stamp)
assert_not_contains "$R" "Recently used" "stamp: no recently used (others' profiles)"
assert_contains "$R" "row | ~/decal-me.tar.gz" "stamp: the stamp file to update"
D2='{"entries": [], "notes": [], "signed_in": false, "active": "/x/folder"}'
R=$(rows "$D2" apply); assert_contains "$R" "head | Active |" "an active profile listed nowhere else: its own group"
R=$(rows "$D2" stamp); assert_contains "$R" "row | ~/decal-me.tar.gz | the usual place" "stamp: the usual file offered when missing"
D3='{"entries": [], "notes": [], "signed_in": true, "loading": true, "active": ""}'
assert_contains "$(rows "$D3" apply)" "note | Looking for your profiles…" "loading: says so"

# the cursor follows the profile, not the row number: the active GitHub profile shown alone while loading,
# then listed under On GitHub when it arrives (with a profile above it)
cur() { python3 -c "import sys,json; sys.path.insert(0, '$REPO/lib'); import ui
a, b = (ui.browser_rows(json.loads(x), 'apply', 'me') for x in sys.argv[1:3])
i = ui.pick_row(a, None, None); k = ui.row_key(a[i]); j = ui.pick_row(b, k, i); print(b[j][1])" "$1" "$2"; }
L1='{"entries": [], "notes": [], "signed_in": true, "loading": true, "active": "github:me/decal-profile"}'
L2='{"entries": [{"kind": "github", "source": "github:me/decal-aaa", "name": "me/decal-aaa", "private": true, "updated": "", "modules": 1, "active": false},
 {"kind": "github", "source": "github:me/decal-profile", "name": "me/decal-profile", "private": true, "updated": "", "modules": 1, "active": true}],
 "notes": [], "signed_in": true, "active": "github:me/decal-profile"}'
assert_eq "$(cur "$L1" "$L2")" "me/decal-profile" "cursor stays on the active profile when GitHub fills in"

# whole flows: apply's first Enter still picks the active profile (keystrokes unchanged above); Up from the
# first row wraps to the last, "Enter a profile…";
# Enter a profile… with a folder of someone else's? a local folder is yours: no warning, used, then applied
mkdir -p "$T_TMP/jk-other"; printf '[base]\non = true\n' > "$T_TMP/jk-other/profile.toml"; : > "$LS_TEST_LOG"
D "$REPO/decal" ui -- 1 "UNTIL:Sign in to see" UP ENTER "UNTIL:tab completes" "$T_TMP/jk-other" ENTER WAIT ENTER WAIT ENTER WAIT ENTER WAIT ENTER q
assert_contains "$(cat "$T_TMP/screen")" "$ decal use $T_TMP/jk-other" "enter a profile: used (j and k typed as letters, not moves)"
assert_contains "$(cat "$T_TMP/screen")" "Stuck on:" "...then applied (base may already be up to date from earlier flows)"
# usb: the command the menu runs, drive labels, the stick menu
py2() { python3 -c "import sys, json; sys.path.insert(0, '$REPO/lib'); import ui; print($1)"; }
assert_eq "$(py2 'ui.usb_cmd("github:me/p", "saved-key", "newest", False, "/run/media/me/Ventoy")')" \
  "['usb', '--from', 'github:me/p', '--how', 'saved-key', '--decal', 'newest', '--to', '/run/media/me/Ventoy']" "usb_cmd"
assert_eq "$(py2 'ui.usb_cmd("/p", "copy", "copy", True, "folder")')" "['usb', '--from', '/p', '--how', 'copy', '--decal', 'copy', '--to', 'folder', '--arm']" "usb_cmd: ARM, folder"
assert_eq "$(py2 'ui.drive_label({"label": "Ventoy", "size": 57700000000, "mount": "/m", "ventoy": True, "isos": 14})')" "Ventoy · 14 ISOs · 57.7 GB" "drive label: Ventoy"
assert_eq "$(py2 'ui.drive_label({"label": "SPARE", "size": 8000000000, "mount": ""})')" "SPARE · 8.0 GB · not mounted" "drive label: unmounted"
assert_eq "$(py2 '[w for k, w, l in ui.STICK_ITEMS]')" "['apply-all', 'choose', 'preview', 'remove-all', 'status', 'other', 'full']" "stick menu: the order"
assert_eq "$(py2 'ui.stick_header({"profile": "github:me/p"}, "just now")')" "From your USB stick: me/p · updated just now" "stick header"
assert_eq "$(py2 'ui.stick_header({"profile": "copy"}, "")')" "From your USB stick: the profile copy on it" "stick header: a copy"
# stick mode: started from a stick, the menu shows the header and its choices
SK="$T_TMP/sk/.Decal"; mkdir -p "$SK"; printf 'profile=github:me/p\nkey=saved\ndecal=newest\n' > "$SK/stick.conf"
DECAL_STICK="$SK" D "$REPO/decal" ui -- q
assert_contains "$(cat "$T_TMP/screen")" "From your USB stick: me/p" "stick mode: header"
assert_contains "$(cat "$T_TMP/screen")" "Apply everything" "stick mode: its choices"
assert_contains "$(cat "$T_TMP/screen")" "Full menu" "stick mode: the way to everything else"
t_done
