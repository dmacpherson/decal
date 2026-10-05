#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export DECAL_MODULES_DIR="$REPO/tests/fixtures/modules-apply" DECAL_PLATFORM=fedora
export LS_TEST_LOG="$T_TMP/log"; : > "$LS_TEST_LOG"
export DECAL_PROFILE_HOME="$T_TMP/home/profile"; unset DECAL_PROFILE
S="$REPO/decal"
P="$T_TMP/myprof"; mkdir -p "$P"; printf '[p1]\nword = "one"\n' > "$P/profile.toml"

# directory: symlinked, then only profiled modules are added
"$S" apply "$P" >/dev/null 2>&1; assert_eq "$?" "0" "apply dir rc"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "dir profile is a symlink"
assert_eq "$(tr '\n' ' ' < "$LS_TEST_LOG")" "p1 add one " "adds only modules in the profile"
# re-applying never removes modules the profile doesn't mention
: > "$LS_TEST_LOG"; "$S" apply "$P" >/dev/null 2>&1
assert_not_contains "$(cat "$LS_TEST_LOG")" "remove" "apply never removes"
out=$("$S" --sync apply "$P" 2>&1); assert_eq "$?" "1" "no --sync option"
# status shows not in profile
assert_contains "$("$S" status p2 2>&1)" "not in profile" "status: not in profile"
# a successful apply tidies the download cache
export DECAL_CACHE="$T_TMP/cache"; mkdir -p "$DECAL_CACHE/rel-9999.tmp"
"$S" apply "$P" >/dev/null 2>&1; assert_nofile "$DECAL_CACHE/rel-9999.tmp" "apply prunes the cache"
# tarball with one top-level folder; replaces the symlink with a real dir
mkdir -p "$T_TMP/t/prof"; printf '[p2]\nword = "two"\n' > "$T_TMP/t/prof/profile.toml"; tar -czf "$T_TMP/p.tar.gz" -C "$T_TMP/t" prof
: > "$LS_TEST_LOG"; "$S" apply "$T_TMP/p.tar.gz" >/dev/null 2>&1
[[ -L $DECAL_PROFILE_HOME ]] && _t_fail "tarball profile should be a real dir"
assert_eq "$(tr '\n' ' ' < "$LS_TEST_LOG")" "p2 add two " "tarball applied"
# git URL: clone, then re-apply pulls
G="$T_TMP/gitprof"; mkdir -p "$G"; printf '[p1]\nword = "g1"\n' > "$G/profile.toml"
git -C "$G" init -q; git -C "$G" -c user.name=t -c user.email=t@t add -A; git -C "$G" -c user.name=t -c user.email=t@t commit -qm 1
: > "$LS_TEST_LOG"; "$S" apply "file://$G" >/dev/null 2>&1; assert_contains "$(cat "$LS_TEST_LOG")" "p1 add g1" "git clone applied"
assert_contains "$(ls -d "$DECAL_PROFILE_HOME".old-*)" ".old-" "previous profile kept as a dated backup"
printf '[p1]\nword = "g2"\n' > "$G/profile.toml"; git -C "$G" -c user.name=t -c user.email=t@t commit -qam 2
: > "$LS_TEST_LOG"; "$S" apply "file://$G" >/dev/null 2>&1; assert_contains "$(cat "$LS_TEST_LOG")" "p1 add g2" "re-apply pulls"
# export is gone: decal stamp saves setups now (tests/test_stamp.sh)
out=$("$S" export x.tar.gz 2>&1); assert_eq "$?" "1" "export is gone (decal stamp replaces it)"
# fetch runs module_fetch for profiled modules
: > "$LS_TEST_LOG"; "$S" fetch >/dev/null 2>&1; assert_eq "$(cat "$LS_TEST_LOG")" "p1 fetch" "fetch"
# a failed fetch names the source and reason
P3="$T_TMP/failprof"; mkdir -p "$P3"; printf '[p1]\nword = "fail"\n' > "$P3/profile.toml"
out=$("$S" --profile "$P3" fetch 2>&1); assert_eq "$?" "1" "failed fetch rc"
assert_contains "$out" "https://x.invalid/y" "failed fetch shows the URL and reason"
# dry-run apply never changes the active profile
before=$(readlink -f "$DECAL_PROFILE_HOME"); "$S" --dry-run apply "$P" >/dev/null 2>&1
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$before" "dry-run apply leaves the active profile"
# bad sources
out=$("$S" apply "$T_TMP/nope" 2>&1); assert_eq "$?" "1" "unknown source rc"
mkdir -p "$T_TMP/empty"; out=$("$S" apply "$T_TMP/empty" 2>&1); assert_contains "$out" "has no profile.toml" "dir without profile.toml"
# re-applying the active profile's own path is a no-op for the profile (real dir and symlink)
: > "$LS_TEST_LOG"; out=$("$S" apply "$DECAL_PROFILE_HOME" 2>&1); assert_eq "$?" "0" "apply active (real dir) rc"
assert_file "$DECAL_PROFILE_HOME/profile.toml" "active real-dir profile kept"
assert_contains "$(cat "$LS_TEST_LOG")" "p1 add g2" "active profile re-applied"
"$S" apply "$P" >/dev/null 2>&1; "$S" apply "$DECAL_PROFILE_HOME" >/dev/null 2>&1
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "active symlink not turned into a self-loop"
# an invalid profile never replaces the active one
B="$T_TMP/bad"; mkdir -p "$B"; printf '[p1]
bogus = 1
' > "$B/profile.toml"
out=$("$S" apply "$B" 2>&1); assert_eq "$?" "1" "invalid profile rc"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "invalid profile left the active one in place"
printf '[p1]
bogus = 1
' > "$T_TMP/t/prof/profile.toml"; tar -czf "$T_TMP/bad.tar.gz" -C "$T_TMP/t" prof
out=$("$S" apply "$T_TMP/bad.tar.gz" 2>&1); assert_eq "$?" "1" "invalid tarball rc"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "invalid tarball left the active one in place"
# earlier backups are never deleted
printf '[p2]\nword = "two"\n' > "$T_TMP/t/prof/profile.toml"; tar -czf "$T_TMP/p.tar.gz" -C "$T_TMP/t" prof
n0=$(ls -d "$DECAL_PROFILE_HOME".old* 2>/dev/null | wc -l)
"$S" apply "$T_TMP/p.tar.gz" >/dev/null 2>&1; "$S" apply "$T_TMP/p.tar.gz" >/dev/null 2>&1
assert_eq "$(ls -d "$DECAL_PROFILE_HOME".old* | wc -l)" "$((n0 + 1))" "each replaced real-dir profile kept as its own backup"
# check refuses a folder without profile.toml
out=$(python3 "$REPO/lib/profile.py" check --profile "$T_TMP/empty" --modules "$DECAL_MODULES_DIR" 2>&1); assert_eq "$?" "2" "check: missing profile.toml fails"
assert_contains "$out" "no profile.toml" "check: missing profile.toml message"
# in a terminal: one line per module with a spinner; details only in the log; notes/warnings still shown
# run in a pseudo-terminal; strip colours and the spinner's line rewrites (\r, erase-line) for matching
tty_run() { python3 -c 'import pty,sys; sys.exit(pty.spawn(sys.argv[1:]) >> 8)' "$@" | sed 's/\x1b\[[0-9;]*[mK]//g; s/\r$//'; return "${PIPESTATUS[0]}"; }
P4="$T_TMP/ttyprof"; mkdir -p "$P4"; printf '[p1]\nword = "tty"\n' > "$P4/profile.toml"
out=$(tty_run "$S" --profile "$P4" add p1 2>&1); rc=$?
assert_eq "$rc" "0" "tty run rc"
assert_contains "$out" "✓ add p1" "tty: module done line"
assert_not_contains "$out" "p1 detail line" "tty: module chatter never on screen, not even as the spinner's hint"
assert_contains "$out" "doing p1 things" "tty: the module's step name is the spinner's hint"
assert_contains "$out" "p1 heads-up" "tty: warnings still shown"
assert_contains "$(cat "$(readlink -f "$DECAL_USER_STATE/logs/last.log")")" "p1 detail line" "tty: chatter kept in the log"
out=$(tty_run "$S" --verbose --profile "$P4" add p1 2>&1)
assert_contains "$out" "p1 detail line" "--verbose shows everything"
assert_contains "$out" "doing p1 things" "--verbose shows steps as plain lines"
assert_not_contains "$(cat "$(readlink -f "$DECAL_USER_STATE/logs/last.log")")" "::step::" "no step markers in the log"
printf '[p1]\nword = "boom"\n' > "$P4/profile.toml"
out=$(tty_run "$S" --profile "$P4" add p1 2>&1); rc=$?
assert_eq "$rc" "1" "tty failure rc"
assert_contains "$out" "✗ add p1" "tty: failed module marked"
assert_contains "$out" "boom detail" "tty: a failed module's last lines are shown"
# use: make a profile active without applying it
U="$T_TMP/usethis"; mkdir -p "$U"; printf '[p1]\nword = "used"\n' > "$U/profile.toml"; : > "$LS_TEST_LOG"
"$S" use "$U" >/dev/null 2>&1; assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$U")" "use: the active profile"
assert_eq "$(cat "$LS_TEST_LOG")" "" "use: nothing applied"
# apply SOURCE MODULE...: that profile, only those modules
A="$T_TMP/twomods"; mkdir -p "$A"; printf '[p1]\nword = "one"\n[p2]\nword = "two"\n' > "$A/profile.toml"; : > "$LS_TEST_LOG"
"$S" apply "$A" p2 >/dev/null 2>&1; assert_eq "$?" "0" "apply SOURCE MODULE rc"
assert_eq "$(cat "$LS_TEST_LOG")" "p2 add two" "apply SOURCE MODULE: just that module"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$A")" "...and the profile is the active one"
# a .zip profile, and a link to one is refused over plain http
mkdir -p "$T_TMP/z"; printf '[p2]\nword = "zip"\n' > "$T_TMP/z/profile.toml"
(cd "$T_TMP/z" && python3 -c 'import zipfile; z=zipfile.ZipFile("../p.zip","w"); z.write("profile.toml"); z.close()')
"$S" apply "$T_TMP/p.zip" >/dev/null 2>&1; assert_eq "$?" "0" "a .zip profile applies"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "$T_TMP/p.zip" "...its source recorded"
out=$("$S" apply http://example.com/p.zip 2>&1); assert_eq "$?" "1" "http link: refused"; assert_contains "$out" "use an https:// link" "...says why"
# write new, then swap: a profile that can't be put in place leaves the active one whole
"$S" apply "$T_TMP/p.tar.gz" >/dev/null 2>&1; before=$(cat "$DECAL_PROFILE_HOME/profile.toml")
stub cp 'case "$*" in *.decal-new*) exit 1;; esac; exec /usr/bin/cp "$@"'
"$S" apply "$T_TMP/p.zip" >/dev/null 2>&1; assert_eq "$?" "1" "the new profile can't be put in place: fails"
assert_eq "$(cat "$DECAL_PROFILE_HOME/profile.toml")" "$before" "...the active profile is untouched"
rm -f "$STUBS/cp"
"$S" apply "$T_TMP/p.zip" >/dev/null 2>&1; assert_eq "$(ls -A "$(dirname "$DECAL_PROFILE_HOME")" | grep -c 'decal-new\|decal-old')" "0" "a normal apply leaves nothing beside it"
# a git profile with a link that leads out of it is refused (a theme or path could go through it)
GR="$T_TMP/gitprof"; mkdir -p "$GR"; cp "$P/profile.toml" "$GR/"; ln -s /etc "$GR/escape"
git -C "$GR" init -q; git -C "$GR" -c user.email=t@t -c user.name=t add -A; git -C "$GR" -c user.email=t@t -c user.name=t commit -qm p
out=$("$S" --yes use "file://$GR" 2>&1); assert_eq "$?" "1" "git source with a link out: refused"
assert_contains "$out" "a link that leads outside it: escape" "...says which"
t_done
