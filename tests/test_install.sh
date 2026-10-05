#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
stub gh 'exit 1'; unset DISPLAY WAYLAND_DISPLAY
# install.sh, decal's self-update and github: profiles against a fake GitHub (a curl stub serving files; no network)
WEB="$T_TMP/web"; mkdir -p "$WEB"; export WEB
key() { printf '%s' "$1" | sed 's#[/:@]#_#g'; }
serve() { cp "$2" "$WEB/$(key "$1")"; }                       # serve URL FILE
serve_text() { printf '%s' "$2" > "$WEB/$(key "$1")"; }       # serve_text URL TEXT
unserve() { rm -f "$WEB/$(key "$1")"; }
stub curl '
url=${@: -1}; out=""; w=""; hdr=""
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift;; -w) w=$2; shift;; -H) hdr=${2#@}; shift;; esac; shift; done
f="$WEB/$(printf "%s" "$url" | sed "s#[/:@]#_#g")"
if [ "$hdr" = - ]; then hdr="$STUBS/stdin-header"; cat > "$hdr"; fi   # -H @-: the header arrives on stdin
if [ -n "$hdr" ]; then cat "$hdr" >> "$STUBS/headers" 2>/dev/null; echo >> "$STUBS/headers"; fi
if [ -e "$f" ] && { [ ! -e "$f.token" ] || grep -qF "$(cat "$f.token")" "$hdr" 2>/dev/null; }; then
  if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi; [ -z "$w" ] || printf 200; exit 0
fi
[ -z "$w" ] || { printf 404; exit 0; }; exit 22'
API=https://api.github.com/repos/dmacpherson/decal; DL=https://github.com/dmacpherson/decal
# a release: decal's own files (+ a marker to tell versions apart), and its checksum
release() {  # release TAG
  local d="$T_TMP/rel/$1"; mkdir -p "$d/decal"
  cp -a "$REPO/decal" "$REPO/install.sh" "$REPO/lib" "$REPO/modules" "$REPO/usb" "$d/decal/"; echo "$1" > "$d/decal/MARK"
  mkdir -p "$d/decal/usb/bin"; echo "x86 $1" > "$d/decal/usb/bin/Decal-x86_64"; echo "arm $1" > "$d/decal/usb/bin/Decal-aarch64"   # as build.yml adds them
  tar -czf "$d/decal.tar.gz" -C "$d" decal; (cd "$d" && sha256sum decal.tar.gz > decal.tar.gz.sha256)
  serve "$DL/releases/download/$1/decal.tar.gz" "$d/decal.tar.gz"; serve "$DL/releases/download/$1/decal.tar.gz.sha256" "$d/decal.tar.gz.sha256"
}
latest() { serve_text "$API/releases/latest" "{\"tag_name\": \"$1\"}"; }
H="$XDG_DATA_HOME/decal/app"; BIN="$HOME/.local/bin"
# decal's own data (module files) lives next to the install and must survive installs and updates
mkdir -p "$XDG_DATA_HOME/decal/icons"; echo logo > "$XDG_DATA_HOME/decal/icons/logo.svg"
mkdir -p "$T_TMP/mods"; cp -a "$REPO/tests/fixtures/modules/eee-conf" "$REPO/tests/fixtures/modules/aaa-ok" "$T_TMP/mods/"
export DECAL_MODULES_DIR="$T_TMP/mods" DECAL_PLATFORM=fedora LS_TEST_LOG="$T_TMP/log"; : > "$LS_TEST_LOG"
export DECAL_PROFILE_HOME="$T_TMP/active"

# first install: the newest release, checksum checked, linked into ~/.local/bin
release v1.0.0; latest v1.0.0
out=$(bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "install rc"
assert_eq "$(cat "$H/VERSION")" "v1.0.0" "newest release installed"
assert_contains "$(grep releases/latest "$STUBS/calls")" "--proto =https --proto-redir =https" "installer downloads: https only, no http redirect"; assert_eq "$(cat "$H/MARK")" "v1.0.0" "its files"
assert_eq "$(readlink "$BIN/decal")" "$H/decal" "decal linked into ~/.local/bin"
assert_file "$H/.installed" "marked as an install (it updates itself)"; assert_eq "$(cat "$H/.channel")" "latest" "channel remembered"
assert_contains "$out" "add $BIN to your PATH" "says when ~/.local/bin isn't on PATH"
assert_eq "$("$BIN/decal" version)" "decal v1.0.0 (latest)" "decal version"
out=$(bash "$REPO/install.sh" --update 2>&1); assert_contains "$out" "decal v1.0.0 is up to date" "update when current: nothing downloaded"
: > "$STUBS/calls"; out=$(bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "installing again rc"
assert_contains "$out" "decal v1.0.0 is already installed and up to date" "installing again: says so"
assert_not_contains "$(calls)" "decal.tar.gz" "...and downloads nothing"
rm "$BIN/decal"; bash "$REPO/install.sh" >/dev/null 2>&1; assert_eq "$(readlink "$BIN/decal")" "$H/decal" "...but puts back a missing link"
: > "$STUBS/calls"; out=$(DECAL_REINSTALL=1 bash "$REPO/install.sh" 2>&1)
assert_contains "$(calls)" "decal.tar.gz" "DECAL_REINSTALL=1: downloaded again"; assert_contains "$out" "installed in" "...and installed"
# a damaged download changes nothing
release v1.0.1; latest v1.0.1; echo "0000 decal.tar.gz" > "$T_TMP/bad"; serve "$DL/releases/download/v1.0.1/decal.tar.gz.sha256" "$T_TMP/bad"
out=$(bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "checksum mismatch rc"
assert_contains "$out" "checksum mismatch" "says so"; assert_eq "$(cat "$H/VERSION")" "v1.0.0" "the installed copy is untouched"
assert_eq "$(bash "$H/install.sh" --check; echo "rc=$?")" "v1.0.1
rc=0" "--check: names the newer version"
latest v1.0.0; assert_eq "$(bash "$H/install.sh" --check; echo "rc=$?")" "rc=1" "--check: nothing newer"

# every run updates decal first when a newer version is out, then runs the command on it
release v1.1.0; latest v1.1.0
out=$("$BIN/decal" list 2>&1); assert_eq "$?" "0" "self-update run rc"
assert_contains "$out" "decal v1.1.0 is out (you have v1.0.0): updating first" "says it updates first"
assert_contains "$out" "aaa-ok" "...then runs the command"
assert_eq "$(cat "$H/MARK")" "v1.1.0" "now on the new version"
release v1.2.0; latest v1.2.0
"$BIN/decal" --no-update list >/dev/null 2>&1; assert_eq "$(cat "$H/MARK")" "v1.1.0" "--no-update: not updated"
DECAL_NO_UPDATE=1 "$BIN/decal" list >/dev/null 2>&1; assert_eq "$(cat "$H/MARK")" "v1.1.0" "DECAL_NO_UPDATE=1: not updated"
out=$("$BIN/decal" update 2>&1); assert_contains "$out" "decal updated: v1.1.0 -> v1.2.0" "decal update"
unserve "$API/releases/latest"
out=$("$BIN/decal" list 2>&1); assert_eq "$?" "0" "GitHub unreachable: the command still runs"; assert_contains "$out" "aaa-ok" "(on the installed version)"
# a git checkout never updates itself (and never asks GitHub)
: > "$STUBS/calls"; "$REPO/decal" list >/dev/null 2>&1; assert_not_contains "$(calls)" "curl" "git checkout: no update check"
out=$("$REPO/decal" update 2>&1); assert_eq "$?" "1" "git checkout: decal update refused"; assert_contains "$out" "update it with git pull" "and says how"
# a branch: its newest commit, no checksum (GitHub makes that archive on the fly)
serve_text "$API/commits/main" '{"sha": "0123456789abcdef0123456789abcdef01234567"}'
serve "$DL/archive/0123456789abcdef0123456789abcdef01234567.tar.gz" "$T_TMP/rel/v1.2.0/decal.tar.gz"
DECAL_VERSION=main bash "$REPO/install.sh" >/dev/null 2>&1
assert_eq "$(cat "$H/VERSION")" "main@0123456789ab" "DECAL_VERSION=main: the branch's commit"; assert_eq "$(cat "$H/.channel")" "main" "and stays on it"
# installed somewhere else: decal checks and updates that copy, linked where it was before
O="$T_TMP/elsewhere"; latest v1.1.0
DECAL_VERSION=latest DECAL_HOME="$O/decal" DECAL_BIN="$O/bin" bash "$REPO/install.sh" >/dev/null 2>&1
latest v1.2.0; out=$("$O/bin/decal" list 2>&1)
assert_contains "$out" "decal v1.2.0 is out (you have v1.1.0)" "an install elsewhere: compared with itself"
assert_eq "$(cat "$O/decal/MARK")" "v1.2.0" "and updated in place"; assert_eq "$(readlink "$O/bin/decal")" "$O/decal/decal" "link kept where it was"
out=$("$O/bin/decal" list 2>&1); assert_not_contains "$out" "is out" "then up to date"
assert_eq "$(cat "$XDG_DATA_HOME/decal/icons/logo.svg")" "logo" "decal's data folder untouched by installs and updates"
mkdir -p "$T_TMP/notdecal"; echo mine > "$T_TMP/notdecal/file"
out=$(DECAL_HOME="$T_TMP/notdecal" bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "a folder that isn't an install: refused"
assert_eq "$(cat "$T_TMP/notdecal/file")" "mine" "and left as it was"
out=$(DECAL_FAKE_EUID=0 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "root refused"; assert_contains "$out" "not root" "says why"

# no profile given, in a terminal: the menu opens (not with DECAL_NO_MENU, and never without a terminal)
python3 "$REPO/tests/fixtures/drive_ui.py" "$T_TMP/screen" bash "$REPO/install.sh" -- q
assert_contains "$(cat "$T_TMP/screen")" "stick it on" "the one-liner without a profile opens the menu"
DECAL_NO_MENU=1 python3 "$REPO/tests/fixtures/drive_ui.py" "$T_TMP/screen" bash "$REPO/install.sh" -- q
assert_not_contains "$(cat "$T_TMP/screen")" "stick it on" "DECAL_NO_MENU=1: no menu"
# install + apply in one go: the arguments go to decal apply
latest v1.2.0; rm -rf "$H"; P="$T_TMP/myprofile"; mkdir -p "$P"; printf '[eee-conf]\nword = "one-liner"\n' > "$P/profile.toml"
DECAL_VERSION=latest bash "$REPO/install.sh" "$P" >/dev/null 2>&1 < /dev/null; assert_eq "$?" "0" "install + apply rc"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add one-liner" "the profile was applied"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "and is the active profile"
: > "$LS_TEST_LOG"; : > "$STUBS/calls"; printf '[eee-conf]\nword = "again"\n' > "$P/profile.toml"
DECAL_VERSION=latest bash "$REPO/install.sh" "$P" >/dev/null 2>&1 < /dev/null
assert_contains "$(cat "$LS_TEST_LOG")" "eee add again" "the one-liner again: applies the profile"; assert_not_contains "$(calls)" "decal.tar.gz" "...without downloading decal again"

# `stamp`: install, then stamp this machine (whatever follows goes to decal stamp)
DECAL_VERSION=latest bash "$REPO/install.sh" stamp -dr > "$T_TMP/o" 2>&1 < /dev/null
assert_contains "$(cat "$T_TMP/o")" "stamping this machine" "the one-liner with stamp: stamps"
assert_contains "$(cat "$T_TMP/o")" "nothing to stamp" "...(these fixture modules have nothing to stamp)"
# github:owner/repo profiles: no git; private repos with a token (never on curl's command line)
mkdir -p "$T_TMP/gh/me-prof-abc"; printf '[eee-conf]\nword = "from-github"\n' > "$T_TMP/gh/me-prof-abc/profile.toml"
tar -czf "$T_TMP/gh.tar.gz" -C "$T_TMP/gh" me-prof-abc
# the fake GitHub serves the repos' tarballs (tb OWNER/REPO FILE [public]); me/prof is private (key s3cret)
GM="$T_TMP/ghmain"; mkdir -p "$GM/tarballs"; echo s3cret > "$GM/token"
fake_github "$GM"; GMPID=$FAKE_PID
tb() { cp "$2" "$GM/tarballs/${1/\//_}.tar.gz"; if [[ ${3:-} == public ]]; then : > "$GM/tarballs/${1/\//_}.public"; fi; }
tb me/prof "$T_TMP/gh.tar.gz"
: > "$LS_TEST_LOG"; : > "$STUBS/calls"
out=$(GITHUB_TOKEN=s3cret "$REPO/decal" --yes apply github:me/prof 2>&1); assert_eq "$?" "0" "github: apply rc"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add from-github" "github: profile applied"
assert_contains "$(cat "$GM/log")" "GET /repos/me/prof/tarball auth=Bearer s3cret" "token sent as a header"
assert_not_contains "$(cat "$GM/codeload_log")" "s3cret" "...and not passed on to the download host"
assert_not_contains "$(calls)" "s3cret" "token not on the command line"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "source recorded"
printf '[eee-conf]\nword = "newer"\n' > "$T_TMP/gh/me-prof-abc/profile.toml"; tar -czf "$T_TMP/gh.tar.gz" -C "$T_TMP/gh" me-prof-abc
tb me/prof "$T_TMP/gh.tar.gz"
GITHUB_TOKEN=s3cret "$REPO/decal" --yes apply github:me/prof >/dev/null 2>&1
assert_contains "$(cat "$DECAL_PROFILE_HOME/profile.toml")" "newer" "applied again: the newer copy"
assert_eq "$(find "$T_TMP" -maxdepth 1 -name 'active.old-*' | wc -l)" "0" "no backup of a download from the same source"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply github:me/prof 2>&1 < /dev/null)
assert_eq "$?" "1" "private repo without a token (no terminal to ask in): fails"
assert_contains "$out" "github:me/prof not found or not allowed (private? set GITHUB_TOKEN" "and says how to fix it"
# no key: decal asks, signs in (the fake GitHub's Decal app), and uses that key for this run only
G="$T_TMP/ghapi"; mkdir -p "$G"; echo s3cret > "$G/token"; echo me/prof > "$G/seed"; echo ok > "$G/device_script"
fake_github "$G" --keep-env; GHPID=$FAKE_PID; FAKE=$FAKE_URL   # its own fake, beside the main one
mkdir -p "$G/tarballs"; cp "$T_TMP/gh.tar.gz" "$G/tarballs/me_prof.tar.gz"
printf '1\n' > "$T_TMP/keys"; : > "$LS_TEST_LOG"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_GITHUB="$FAKE" DECAL_GITHUB_API="$FAKE" DECAL_GITHUB_APP_READ=Iv-read:decal \
  DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$REPO/decal" --yes apply github:me/prof 2>&1)
assert_eq "$?" "0" "private profile, no key: signed in and applied"
assert_contains "$(cat "$T_TMP/screen")" "2. Enter WDJB-MJHT" "the sign-in screen was shown"
assert_contains "$(cat "$G/device_log")" "client_id=Iv-read" "with the read app"
assert_eq "$(grep -rl s3cret "$HOME" 2>/dev/null | wc -l)" "0" "the key isn't saved anywhere under HOME"
kill "$GHPID" 2>/dev/null
# any source: a GitHub link and owner/name are the same github: source; the source is remembered
: > "$LS_TEST_LOG"
GITHUB_TOKEN=s3cret "$REPO/decal" --yes apply https://github.com/me/prof >/dev/null 2>&1; assert_eq "$?" "0" "a GitHub link applies"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "...as github:me/prof"
assert_eq "$(head -1 "$DECAL_USER_STATE/recent" | cut -f1)" "github:me/prof" "...and is remembered as recently used"
# not yours: a stranger's repo without a terminal and without --yes stops, before anything changes
mkdir -p "$T_TMP/gh2/stranger-prof-1"; printf '[eee-conf]\nword = "stranger"\n' > "$T_TMP/gh2/stranger-prof-1/profile.toml"
tar -czf "$T_TMP/gh2.tar.gz" -C "$T_TMP/gh2" stranger-prof-1; tb stranger/prof "$T_TMP/gh2.tar.gz" public
: > "$LS_TEST_LOG"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply stranger/prof 2>&1 < /dev/null); assert_eq "$?" "1" "someone else's profile, no terminal: stops"
assert_contains "$out" "this profile is from stranger/prof, not you" "...says whose it is"
assert_contains "$out" "not applied: to apply it anyway, run decal --yes apply github:stranger/prof" "...and how to apply it anyway"
assert_eq "$(cat "$LS_TEST_LOG")" "" "...nothing added"
assert_contains "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "...and the active profile is unchanged"
# with a terminal: p previews (nothing changes), then y applies
printf 'p\ny\n' > "$T_TMP/keys"; : > "$LS_TEST_LOG"; : > "$GM/log"
out=$(env -u GITHUB_TOKEN -u GH_TOKEN DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$REPO/decal" apply stranger/prof 2>&1)
assert_eq "$?" "0" "someone else's profile, previewed then confirmed: applied"
assert_eq "$(grep -o 'p preview' "$T_TMP/screen" | wc -l)" "2" "...asked, previewed, asked again"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add stranger" "...then added (the fixture logs during the preview too)"
assert_eq "$(grep -c 'stranger/prof/tarball' "$GM/log")" "1" "...downloaded once: what was previewed is what's applied"
# use alone doesn't make it yours: only applying does
mkdir -p "$T_TMP/gh3/other-x-1"; printf '[eee-conf]\nword = "x"\n' > "$T_TMP/gh3/other-x-1/profile.toml"
tar -czf "$T_TMP/gh3.tar.gz" -C "$T_TMP/gh3" other-x-1; tb other/x "$T_TMP/gh3.tar.gz" public
env -u GITHUB_TOKEN -u GH_TOKEN "$REPO/decal" use other/x >/dev/null 2>&1
assert_not_contains "$(cut -f1 "$DECAL_USER_STATE/recent")" "github:other/x" "use: not remembered as yours"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply other/x 2>&1 < /dev/null); assert_eq "$?" "1" "...so apply still asks"
# now it's recently used: no question next time
: > "$LS_TEST_LOG"
setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply stranger/prof >/dev/null 2>&1 < /dev/null
assert_eq "$?" "0" "recently used: no question"
# install.sh passes --yes with the profile it was given
grep -q 'cmd=(apply --yes)' "$REPO/install.sh"; assert_eq "$?" "0" "the installer applies with --yes"
# a local copy (a decal USB stick): installed without downloading, checksum checked
release v1.5.0; L="$T_TMP/rel/v1.5.0"; : > "$STUBS/calls"
out=$(DECAL_ARCHIVE="$L/decal.tar.gz" DECAL_ARCHIVE_VERSION=v1.5.0 DECAL_NO_MENU=1 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "local copy: installed"
assert_eq "$(cat "$H/VERSION")" "v1.5.0" "...that version"; assert_eq "$(cat "$H/MARK")" "v1.5.0" "...its files"
assert_not_contains "$(calls)" "curl" "...nothing downloaded"
echo "0000  decal.tar.gz" > "$T_TMP/badsum"; cp "$L/decal.tar.gz" "$T_TMP/copy.tar.gz"; cp "$T_TMP/badsum" "$T_TMP/copy.tar.gz.sha256"
out=$(DECAL_ARCHIVE="$T_TMP/copy.tar.gz" DECAL_ARCHIVE_VERSION=v1.6.0 DECAL_NO_MENU=1 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "local copy, bad checksum: refused"
assert_contains "$out" "checksum mismatch" "...says why"; assert_eq "$(cat "$H/VERSION")" "v1.5.0" "...nothing changed"
out=$(DECAL_ARCHIVE="$T_TMP/none.tar.gz" bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "no copy there: refused"
# the dev channel: the rolling "dev" pre-release (named dev-<commit>), checksum checked, remembered, updated
devrel() {  # devrel NAME : a dev build called NAME at releases/download/dev
  local d="$T_TMP/dev/$1"; mkdir -p "$d/decal"
  cp -a "$REPO/decal" "$REPO/install.sh" "$REPO/lib" "$REPO/modules" "$REPO/usb" "$d/decal/"; echo "$1" > "$d/decal/MARK"
  tar -czf "$d/decal.tar.gz" -C "$d" decal; (cd "$d" && sha256sum decal.tar.gz > decal.tar.gz.sha256)
  serve "$DL/releases/download/dev/decal.tar.gz" "$d/decal.tar.gz"; serve "$DL/releases/download/dev/decal.tar.gz.sha256" "$d/decal.tar.gz.sha256"
  serve_text "$API/releases/tags/dev" "{\"tag_name\": \"dev\", \"name\": \"$1\"}"; }
devrel dev-abc1234
out=$(DECAL_VERSION=dev DECAL_NO_MENU=1 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "dev channel: installed"
assert_eq "$(cat "$H/VERSION")" "dev-abc1234" "...the dev build, named by its commit"; assert_eq "$(cat "$H/MARK")" "dev-abc1234" "...its files"
assert_eq "$(cat "$H/.channel")" "dev" "...dev remembered as the channel"
DECAL_HOME="$H" bash "$REPO/install.sh" --check >/dev/null 2>&1; assert_eq "$?" "1" "dev: the same build is up to date"
devrel dev-def5678
assert_eq "$(DECAL_HOME="$H" bash "$REPO/install.sh" --check 2>/dev/null)" "dev-def5678" "dev: a newer dev build is an update"
echo "0000  decal.tar.gz" > "$T_TMP/dsum"; serve "$DL/releases/download/dev/decal.tar.gz.sha256" "$T_TMP/dsum"
out=$(DECAL_NO_MENU=1 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "dev: a damaged download is refused"
# the pages site: /install (main's) and /dev/install (dev's, defaulting to the dev channel)
cp "$REPO/install.sh" "$T_TMP/dev-install.sh"
bash "$REPO/tools/pages-site.sh" "$REPO/install.sh" "$T_TMP/dev-install.sh" "$T_TMP/site" dmacpherson/decal
assert_eq "$(cat "$T_TMP/site/install")" "$(cat "$REPO/install.sh")" "site: /install is main's installer"
assert_contains "$(sed -n 2p "$T_TMP/site/dev/install")" 'DECAL_VERSION=${DECAL_VERSION:-dev}' "site: /dev/install defaults to the dev channel"
bash -n "$T_TMP/site/dev/install"; assert_eq "$?" "0" "site: /dev/install is valid bash"
assert_file "$T_TMP/site/dev/install.sh" "site: /dev/install.sh too"; assert_file "$T_TMP/site/index.html" "site: index"
# decal use asks too (the menu runs decal use, then add): someone else's profile can't slip in through it
mkdir -p "$T_TMP/gh4/third-p-1"; printf '[eee-conf]\nword = "third"\n' > "$T_TMP/gh4/third-p-1/profile.toml"
tar -czf "$T_TMP/gh4.tar.gz" -C "$T_TMP/gh4" third-p-1; tb third/p "$T_TMP/gh4.tar.gz" public
before=$(cat "$DECAL_PROFILE_HOME/.decal-source" 2>/dev/null)
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" use third/p 2>&1 < /dev/null); assert_eq "$?" "1" "use: someone else's profile, no terminal: stops"
assert_contains "$out" "this profile is from third/p, not you" "use: says whose it is"; assert_contains "$out" "not used: to use it anyway, run decal --yes use github:third/p" "use: says how to go on"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source" 2>/dev/null)" "$before" "use: the active profile unchanged"
env -u GITHUB_TOKEN -u GH_TOKEN "$REPO/decal" --yes use third/p >/dev/null 2>&1; assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:third/p" "use --yes: used"
# the new decal is unpacked beside the install (same filesystem): the swap is a rename, never a copy from /tmp
mkdir -p "$T_TMP/ro"; chmod 555 "$T_TMP/ro"; release v1.9.0; latest v1.9.0
out=$(TMPDIR="$T_TMP/ro" DECAL_VERSION=latest DECAL_NO_MENU=1 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "install doesn't depend on /tmp"
assert_eq "$(cat "$H/VERSION")" "v1.9.0" "...the new version in place"
assert_eq "$(ls -A "$(dirname "$H")" | grep -c '^\.decal-new')" "0" "...no leftovers beside it"
chmod 755 "$T_TMP/ro"
# one release download: install.sh --fetch-to DIR fetches, checks and unpacks without installing (audit batch 4)
release v2.0.0; latest v2.0.0; before=$(cat "$H/VERSION")
out=$(DECAL_HOME="$H" DECAL_VERSION=latest bash "$REPO/install.sh" --fetch-to "$T_TMP/f" 2>/dev/null); assert_eq "$?" "0" "--fetch-to: rc"
assert_eq "$(cat "$out/MARK" 2>/dev/null)" "v2.0.0" "--fetch-to: prints the unpacked decal"
assert_eq "$(cat "$H/VERSION")" "$before" "...and installs nothing"
echo "0000  decal.tar.gz" > "$T_TMP/fsum"; serve "$DL/releases/download/v2.0.0/decal.tar.gz.sha256" "$T_TMP/fsum"
DECAL_VERSION=latest bash "$REPO/install.sh" --fetch-to "$T_TMP/f2" >/dev/null 2>&1; assert_eq "$?" "1" "--fetch-to: a damaged download refused"
# decal usb in a checkout without launchers: takes them from the release through install.sh (no curl of its own)
release v2.1.0; latest v2.1.0; mkdir -p "$T_TMP/up"; printf '[eee-conf]\nword = "u"\n' > "$T_TMP/up/profile.toml"
out=$("$REPO/decal" usb --from "$T_TMP/up" --decal online --to "folder:$T_TMP/uf" --yes 2>&1); assert_eq "$?" "0" "usb: launchers from the release"
assert_eq "$(cat "$T_TMP/uf/Decal" 2>/dev/null)" "x86 v2.1.0" "...the release's launcher on the stick"
# an active profile nobody was asked about (made active by an older decal use): add asks first (minors)
A="$DECAL_PROFILE_HOME"; rm -rf "$A"; mkdir -p "$A"; printf '[eee-conf]\nword = "fourth"\n' > "$A/profile.toml"; echo "github:fourth/q" > "$A/.decal-source"
: > "$LS_TEST_LOG"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" add all 2>&1 < /dev/null); assert_eq "$?" "1" "add: a stranger's active profile, never asked: stops"
assert_contains "$out" "this profile is from fourth/q" "...says whose it is"; assert_eq "$(cat "$LS_TEST_LOG")" "" "...nothing added"
setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" --yes add all >/dev/null 2>&1 < /dev/null; assert_eq "$?" "0" "...--yes: added"
setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" add all >/dev/null 2>&1 < /dev/null; assert_eq "$?" "0" "...and not asked again"
# decal use, answered yes, then add (what the menu runs): one question, not two
mkdir -p "$T_TMP/gh5/fifth-r-1"; printf '[eee-conf]\nword = "fifth"\n' > "$T_TMP/gh5/fifth-r-1/profile.toml"
tar -czf "$T_TMP/gh5.tar.gz" -C "$T_TMP/gh5" fifth-r-1; tb fifth/r "$T_TMP/gh5.tar.gz" public
printf 'y\n' > "$T_TMP/keys"
env -u GITHUB_TOKEN -u GH_TOKEN DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" "$REPO/decal" use fifth/r >/dev/null 2>&1; assert_eq "$?" "0" "use: asked, yes"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" add all 2>&1 < /dev/null); assert_eq "$?" "0" "...then add doesn't ask again"
# decal usb on an install that follows a branch: its archive has no launchers (CI builds those), so the latest
# release's are used (minors)
NB="$T_TMP/nobin"; mkdir -p "$NB"; cp -a "$T_TMP/rel/v2.1.0/decal" "$NB/"; rm -rf "$NB/decal/usb/bin"; tar -czf "$NB/a.tar.gz" -C "$NB" decal
serve_text "$API/commits/main" '{"sha": "1111111111111111111111111111111111111111"}'
serve "$DL/archive/1111111111111111111111111111111111111111.tar.gz" "$NB/a.tar.gz"; latest v2.1.0
BR="$T_TMP/branch"; DECAL_VERSION=main DECAL_HOME="$BR/decal" DECAL_BIN="$BR/bin" DECAL_NO_MENU=1 bash "$REPO/install.sh" >/dev/null 2>&1
rm -rf "$XDG_CACHE_HOME/decal/usb-bin"
out=$(DECAL_NO_UPDATE=1 "$BR/decal/decal" usb --from "$T_TMP/up" --decal online --to "folder:$T_TMP/bf" --yes 2>&1); assert_eq "$?" "0" "usb on a branch install: rc"
assert_eq "$(cat "$T_TMP/bf/Decal" 2>/dev/null)" "x86 v2.1.0" "...the latest release's launcher"
kill "$GMPID" 2>/dev/null
t_done
