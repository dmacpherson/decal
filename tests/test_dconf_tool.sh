#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
# Isolated dconf: private user db, private session bus. Never touches the real desktop.
mkdir -p "$T_TMP/cfg"; echo "user-db:user" > "$T_TMP/profile"
export XDG_CONFIG_HOME="$T_TMP/cfg" DCONF_PROFILE="$T_TMP/profile"
T="python3 $REPO/lib/dconf_tool.py"; INI="$REPO/tests/fixtures/dconf/test.ini"; PREV="$T_TMP/prev.json"
body() {
  dconf write /org/gnome/desktop/interface/clock-format "'12h'"   # pre-existing user value
  dconf write /org/gnome/desktop/app-folders/folder-children "['Utilities']"
  echo "S0=$($T status --base / --ini "$INI" --prev "$PREV" | tail -1)"
  $T apply --base / --ini "$INI" --prev "$PREV" --merge /org/gnome/desktop/app-folders/folder-children --subst "@HOME@=/home/x" 2>"$T_TMP/err"
  echo "ERR=$(tr '\n' '|' < "$T_TMP/err")"
  echo "A=$(dconf read /org/gnome/desktop/interface/accent-color)"
  echo "C=$(dconf read /org/gnome/desktop/interface/clock-format)"
  echo "F=$(dconf read /org/gnome/desktop/app-folders/folder-children)"
  echo "N=$(dconf read /org/gnome/desktop/app-folders/folders/MyFolder/name)"
  echo "K=$(dconf read /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command)"
  echo "BG=$(dconf read /org/gnome/desktop/background/picture-uri)"
  echo "BOGUS=$(dconf read /org/gnome/desktop/interface/this-key-does-not-exist)"
  echo "S1=$($T status --base / --ini "$INI" --prev "$PREV" --merge /org/gnome/desktop/app-folders/folder-children --subst "@HOME@=/home/x" | tail -1)"
  # second apply must not overwrite the recorded originals
  dconf write /org/gnome/desktop/interface/clock-format "'24h'"
  $T apply --base / --ini "$INI" --prev "$PREV" --merge /org/gnome/desktop/app-folders/folder-children --subst "@HOME@=/home/x" 2>/dev/null
  $T remove --base / --prev "$PREV"
  echo "RA=$(dconf read /org/gnome/desktop/interface/accent-color)"
  echo "RC=$(dconf read /org/gnome/desktop/interface/clock-format)"
  echo "RF=$(dconf read /org/gnome/desktop/app-folders/folder-children)"
  echo "RN=$(dconf read /org/gnome/desktop/app-folders/folders/MyFolder/name)"
  echo "PREV_EXISTS=$([[ -e $PREV ]] && echo yes || echo no)"
  $T remove --base / --prev "$PREV"; echo "RM2=$?"
  # merge that added nothing (item already in the schema default, key unset), then the user
  # changes the list themselves: remove must leave the user's change alone
  printf '[org/gnome/desktop/app-folders]\nfolder-children=[%s]\n' "'Utilities'" > "$T_TMP/m.ini"
  dconf reset /org/gnome/desktop/app-folders/folder-children
  $T apply --base / --ini "$T_TMP/m.ini" --prev "$T_TMP/m.json" --merge /org/gnome/desktop/app-folders/folder-children 2>/dev/null
  dconf write /org/gnome/desktop/app-folders/folder-children "['Utilities', 'Mine']"
  $T remove --base / --prev "$T_TMP/m.json"
  echo "USERCHANGE=$(dconf read /org/gnome/desktop/app-folders/folder-children)"
}
export -f body; export T INI PREV T_TMP
out=$(dbus-run-session -- bash -c body 2>/dev/null)
v() { grep "^$1=" <<<"$out" | head -1 | cut -d= -f2-; }
assert_eq "$(v S0)" "not-installed" "status before"
assert_contains "$(v ERR)" "skip (n/a): /org/gnome/desktop/interface/this-key-does-not-exist" "unknown key skipped"
assert_contains "$(v ERR)" "skip (refused): /org/gnome/desktop/background/picture-uri" "background refused"
assert_eq "$(v A)" "'teal'" "applied"; assert_eq "$(v C)" "'24h'" "overwrote user value"
assert_eq "$(v F)" "['Utilities', 'MyFolder']" "merged, order kept"
assert_eq "$(v N)" "'My Folder'" "relocatable schema validated"
assert_eq "$(v K)" "'/home/x/bin/term'" "placeholder substituted"
assert_eq "$(v BG)" "" "refused not written"; assert_eq "$(v BOGUS)" "" "n/a not written"
assert_eq "$(v S1)" "installed" "status after"
assert_eq "$(v RA)" "" "reset (was unset)"; assert_eq "$(v RC)" "'12h'" "restored FIRST original"
assert_eq "$(v RF)" "['Utilities']" "merge undone, user item kept"
assert_eq "$(v RN)" "" "folder key reset"
assert_eq "$(v PREV_EXISTS)" "no" "prev deleted"
assert_eq "$(v USERCHANGE)" "['Utilities', 'Mine']" "merge that added nothing never resets user changes"; assert_eq "$(v RM2)" "0" "remove twice no-op"
# the undo record is replaced whole (a crash can't leave it half-written, which would make remove impossible)
python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import dconf_tool as d; d.save_prev('$T_TMP/prev.json', {'keys': {}})"
i=$(stat -c %i "$T_TMP/prev.json")
python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import dconf_tool as d; d.save_prev('$T_TMP/prev.json', {'keys': {'a': 1}})"
assert_not_contains "$(stat -c %i "$T_TMP/prev.json")" "$i" "save_prev: replaced whole"; assert_contains "$(cat "$T_TMP/prev.json")" '"a": 1' "save_prev: content"
t_done
