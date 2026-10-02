#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
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
if [ -n "$hdr" ]; then cat "$hdr" >> "$STUBS/headers" 2>/dev/null; echo >> "$STUBS/headers"; fi
if [ -e "$f" ] && { [ ! -e "$f.token" ] || grep -qF "$(cat "$f.token")" "$hdr" 2>/dev/null; }; then
  if [ -n "$out" ]; then cp "$f" "$out"; else cat "$f"; fi; [ -z "$w" ] || printf 200; exit 0
fi
[ -z "$w" ] || { printf 404; exit 0; }; exit 22'
API=https://api.github.com/repos/dmacpherson/decal; DL=https://github.com/dmacpherson/decal
# a release: decal's own files (+ a marker to tell versions apart), and its checksum
release() {  # release TAG
  local d="$T_TMP/rel/$1"; mkdir -p "$d/decal"
  cp -a "$REPO/decal" "$REPO/install.sh" "$REPO/lib" "$REPO/modules" "$d/decal/"; echo "$1" > "$d/decal/MARK"
  tar -czf "$d/decal.tar.gz" -C "$d" decal; (cd "$d" && sha256sum decal.tar.gz > decal.tar.gz.sha256)
  serve "$DL/releases/download/$1/decal.tar.gz" "$d/decal.tar.gz"; serve "$DL/releases/download/$1/decal.tar.gz.sha256" "$d/decal.tar.gz.sha256"
}
latest() { serve_text "$API/releases/latest" "{\"tag_name\": \"$1\"}"; }
H="$XDG_DATA_HOME/decal"; BIN="$HOME/.local/bin"
mkdir -p "$T_TMP/mods"; cp -a "$REPO/tests/fixtures/modules/eee-conf" "$REPO/tests/fixtures/modules/aaa-ok" "$T_TMP/mods/"
export DECAL_MODULES_DIR="$T_TMP/mods" DECAL_PLATFORM=fedora LS_TEST_LOG="$T_TMP/log"; : > "$LS_TEST_LOG"
export DECAL_PROFILE_HOME="$T_TMP/active"

# first install: the newest release, checksum checked, linked into ~/.local/bin
release v1.0.0; latest v1.0.0
out=$(bash "$REPO/install.sh" 2>&1); assert_eq "$?" "0" "install rc"
assert_eq "$(cat "$H/VERSION")" "v1.0.0" "newest release installed"; assert_eq "$(cat "$H/MARK")" "v1.0.0" "its files"
assert_eq "$(readlink "$BIN/decal")" "$H/decal" "decal linked into ~/.local/bin"
assert_file "$H/.installed" "marked as an install (it updates itself)"; assert_eq "$(cat "$H/.channel")" "latest" "channel remembered"
assert_contains "$out" "add $BIN to your PATH" "says when ~/.local/bin isn't on PATH"
assert_eq "$("$BIN/decal" version)" "decal v1.0.0 (latest)" "decal version"
out=$(bash "$REPO/install.sh" --update 2>&1); assert_contains "$out" "decal v1.0.0 is up to date" "update when current: nothing downloaded"
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
out=$(DECAL_FAKE_EUID=0 bash "$REPO/install.sh" 2>&1); assert_eq "$?" "1" "root refused"; assert_contains "$out" "not root" "says why"

# install + apply in one go: the arguments go to decal apply
latest v1.2.0; rm -rf "$H"; P="$T_TMP/myprofile"; mkdir -p "$P"; printf '[eee-conf]\nword = "one-liner"\n' > "$P/profile.toml"
DECAL_VERSION=latest bash "$REPO/install.sh" "$P" >/dev/null 2>&1 < /dev/null; assert_eq "$?" "0" "install + apply rc"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add one-liner" "the profile was applied"
assert_eq "$(readlink -f "$DECAL_PROFILE_HOME")" "$(readlink -f "$P")" "and is the active profile"

# github:owner/repo profiles: no git; private repos with a token (never on curl's command line)
mkdir -p "$T_TMP/gh/me-prof-abc"; printf '[eee-conf]\nword = "from-github"\n' > "$T_TMP/gh/me-prof-abc/profile.toml"
tar -czf "$T_TMP/gh.tar.gz" -C "$T_TMP/gh" me-prof-abc
serve https://api.github.com/repos/me/prof/tarball "$T_TMP/gh.tar.gz"; echo "Bearer s3cret" > "$WEB/$(key https://api.github.com/repos/me/prof/tarball).token"
: > "$LS_TEST_LOG"; : > "$STUBS/calls"
out=$(GITHUB_TOKEN=s3cret "$REPO/decal" apply github:me/prof 2>&1); assert_eq "$?" "0" "github: apply rc"
assert_contains "$(cat "$LS_TEST_LOG")" "eee add from-github" "github: profile applied"
assert_contains "$(cat "$STUBS/headers")" "Authorization: Bearer s3cret" "token sent as a header"
assert_not_contains "$(calls)" "s3cret" "token not on the command line"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "github:me/prof" "source recorded"
printf '[eee-conf]\nword = "newer"\n' > "$T_TMP/gh/me-prof-abc/profile.toml"; tar -czf "$T_TMP/gh.tar.gz" -C "$T_TMP/gh" me-prof-abc
serve https://api.github.com/repos/me/prof/tarball "$T_TMP/gh.tar.gz"
GITHUB_TOKEN=s3cret "$REPO/decal" apply github:me/prof >/dev/null 2>&1
assert_contains "$(cat "$DECAL_PROFILE_HOME/profile.toml")" "newer" "applied again: the newer copy"
assert_eq "$(find "$T_TMP" -maxdepth 1 -name 'active.old-*' | wc -l)" "0" "no backup of a download from the same source"
out=$(setsid -w env -u GITHUB_TOKEN -u GH_TOKEN PATH="$PATH" "$REPO/decal" apply github:me/prof 2>&1 < /dev/null)
assert_eq "$?" "1" "private repo without a token (no terminal to ask in): fails"
assert_contains "$out" "github:me/prof not found or not allowed (private? set GITHUB_TOKEN" "and says how to fix it"
t_done
