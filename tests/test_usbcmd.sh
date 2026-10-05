#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
export DECAL_MEDIA="$T_TMP/media" DECAL_PROFILE_HOME="$T_TMP/active"; mkdir -p "$DECAL_MEDIA"
M="$T_TMP/mods"; mkdir -p "$M/live"; echo '{"keys": {"word": {"type": "string", "default": "x"}}}' > "$M/live/schema.json"; : > "$M/live/module.sh"
export DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora
B="$T_TMP/bin"; mkdir -p "$B"; echo x86 > "$B/Decal-x86_64"; echo arm > "$B/Decal-aarch64"; export DECAL_USB_BIN="$B"
P="$T_TMP/prof"; mkdir -p "$P"; printf '[live]\nword = "w"\n' > "$P/profile.toml"
T="$T_TMP/stick"; mkdir -p "$T"
U() { "$REPO/decal" usb "$@" 2>&1; }

# a copy of a local profile, the decal copy, x86 only
out=$(U --from "$P" --to "$T" --yes); assert_eq "$?" "0" "a local profile → a copy on the stick"
assert_eq "$(cat "$T/Decal")" "x86" "the x86 launcher at the root"; assert_nofile "$T/.Decal/Decal-ARM" "no ARM launcher unless asked"
assert_contains "$(cat "$T/.Decal/stick.conf")" "profile=copy" "stick.conf: a copy"; assert_contains "$(cat "$T/.Decal/stick.conf")" "decal=newest" "...newest by default"
assert_contains "$(cat "$T/.Decal/profile/profile.toml")" 'word = "w"' "the profile copied"
assert_file "$T/.Decal/start.sh" "start.sh"; assert_contains "$(cat "$T/.Decal/README.txt")" "Profile:   a copy of $P" "README filled in"
# the decal copy: decal's own files, no .git/tests/docs, and its install.sh installs it
(cd "$T/.Decal" && sha256sum -c decal.tar.gz.sha256 >/dev/null); assert_eq "$?" "0" "decal copy: checksum matches"
L=$(tar -tzf "$T/.Decal/decal.tar.gz"); assert_contains "$L" "decal/decal" "decal copy: decal itself"; assert_contains "$L" "decal/usb/start.sh" "...and the usb files"
assert_not_contains "$L" "decal/.git/" "...no .git"; assert_not_contains "$L" "decal/tests/" "...no tests"; assert_not_contains "$L" "decal/docs/" "...no docs"
DECAL_ARCHIVE="$T/.Decal/decal.tar.gz" DECAL_ARCHIVE_VERSION=vtest DECAL_NO_MENU=1 bash <(tar -xzf "$T/.Decal/decal.tar.gz" -O decal/install.sh) >/dev/null 2>&1
assert_eq "$(cat "$XDG_DATA_HOME/decal/app/VERSION")" "vtest" "decal copy: its install.sh installs it"
# ARM, online only (no copy)
U --from "$P" --to "$T" --decal online --arm --yes >/dev/null
assert_eq "$(cat "$T/.Decal/Decal-ARM")" "arm" "--arm: Decal-ARM in .Decal"; assert_nofile "$T/.Decal/decal.tar.gz" "online: no copy"
# a GitHub profile with a saved key (given explicitly here; normally a Decal Profile sign-in)
mkdir -p "$T_TMP/gh/me-p-1"; cp "$P/profile.toml" "$T_TMP/gh/me-p-1/"; tar -czf "$T_TMP/gh.tar.gz" -C "$T_TMP/gh" me-p-1
G="$T_TMP/ghapi"; mkdir -p "$G/tarballs"; echo s3cret > "$G/token"; cp "$T_TMP/gh.tar.gz" "$G/tarballs/me_p.tar.gz"   # the fake GitHub
fake_github "$G"; GHPID=$FAKE_PID
out=$(DECAL_STICK_KEY=r3ad GITHUB_TOKEN=s3cret U --from me/p --how saved-key --to "$T" --yes); assert_eq "$?" "0" "GitHub + saved key"
assert_contains "$(cat "$T/.Decal/stick.conf")" "profile=github:me/p" "stick.conf: the repo"; assert_contains "$(cat "$T/.Decal/stick.conf")" "key=saved" "...key saved"
assert_eq "$(cat "$T/.Decal/key")" "r3ad" "the given read key, not GITHUB_TOKEN"
assert_eq "$(grep -rl s3cret "$T" | wc -l)" "0" "GITHUB_TOKEN never written to the stick"
GITHUB_TOKEN=s3cret U --from me/p --how sign-in --to "$T" --yes >/dev/null; assert_nofile "$T/.Decal/key" "sign-in: no key on the stick"
assert_contains "$(cat "$T/.Decal/stick.conf")" "key=ask" "...stick.conf says ask"
# a key that can write is never put on a stick: classic and gh tokens refused (before anything is written)
rm -rf "$T"; mkdir -p "$T"
out=$(DECAL_STICK_KEY=ghp_classic GITHUB_TOKEN=s3cret U --from me/p --how saved-key --to "$T" --yes); assert_eq "$?" "1" "a classic token (ghp_): refused"
assert_contains "$out" "can write" "...says why"; assert_nofile "$T/.Decal" "...nothing written"
out=$(DECAL_STICK_KEY=gho_ghlogin GITHUB_TOKEN=s3cret U --from me/p --how saved-key --to "$T" --yes); assert_eq "$?" "1" "a gh token (gho_): refused"
assert_eq "$(python3 -c "import sys; sys.path.insert(0, '$REPO/lib'); import auth; print(auth.scopes_write('repo, read:org'), auth.scopes_write('read:org'), auth.scopes_write(''))")" "True False False" "classic scopes: repo means it can write"
# FAT32: the summary and the stick's README say double-click won't work there
stub findmnt 'echo vfat'; rm -rf "$T"; mkdir -p "$T"
out=$(U --from "$P" --to "$T" --yes); assert_contains "$out" "FAT32" "FAT32: the summary warns"
assert_contains "$(cat "$T/.Decal/README.txt")" "This stick is FAT32" "FAT32: the README says how to start it"
rm -f "$STUBS/findmnt"
# no terminal, no --yes: stops before writing
rm -rf "$T"; mkdir -p "$T"
out=$(setsid -w "$REPO/decal" usb --from "$P" --to "$T" 2>&1 < /dev/null); assert_eq "$?" "1" "no terminal, no --yes: stops"
assert_contains "$out" "--yes" "...says how to go on"; assert_nofile "$T/.Decal" "...nothing written"
# a folder
U --from "$P" --to "folder:$T_TMP/usbfolder" --yes >/dev/null; assert_file "$T_TMP/usbfolder/Decal" "folder target"
# public check
DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$REPO/lib/source.py" public github:me/p >/dev/null 2>&1; assert_eq "$?" "1" "public: GitHub unreachable → not known public"
# an option without its value: says what it needs, no shell jargon (audit batch 3)
out=$("$REPO/decal" usb --how 2>&1); assert_eq "$?" "1" "usb --how alone: fails"
assert_contains "$out" "--how needs saved-key, sign-in, copy or latest" "...says what it needs"; assert_not_contains "$out" "parameter null" "...no shell jargon"
out=$("$REPO/decal" --profile 2>&1); assert_contains "$out" "--profile needs a profile folder" "global option: says what it needs"; assert_not_contains "$out" "line " "...no line numbers"
# GitHub out of reach: says so, not "HTTP 000"
out=$(DECAL_GITHUB_API=http://127.0.0.1:9 "$REPO/decal" --yes use github:me/prof 2>&1); assert_contains "$out" "couldn't reach GitHub to get github:me/prof: check the internet connection" "offline: plain words"
assert_not_contains "$out" "HTTP 000" "...no HTTP code"
# --yes writes without asking, so it never guesses the drive (audit batch 3)
out=$("$REPO/decal" usb --from "$P" --yes 2>&1); assert_eq "$?" "1" "--yes without --to: refused"
assert_contains "$out" "--yes needs --to" "...says what to add"
kill "$GHPID" 2>/dev/null
# the end of input (Ctrl+D, a closed terminal) at "Write these?" writes nothing (review)
mkdir -p "$T_TMP/eof"; out=$(DECAL_TTY_IN=/dev/null DECAL_TTY_OUT=/dev/null "$REPO/decal" usb --from "$P" --decal online --to "folder:$T_TMP/eof/x" 2>&1)
assert_eq "$?" "1" "end of input at the question: stops"; assert_contains "$out" "nothing written" "...says so"; assert_nofile "$T_TMP/eof/x/Decal" "...nothing written"
# the read key is fetched after "Write these?", so answering no never makes one (minors)
printf 'n\n' > "$T_TMP/no"; rm -rf "$T_TMP/k1"; fake_github "$G"
out=$(GITHUB_TOKEN=s3cret DECAL_STICK_KEY=ghp_classic DECAL_TTY_IN="$T_TMP/no" DECAL_TTY_OUT=/dev/null "$REPO/decal" usb --from me/p --how saved-key --to "folder:$T_TMP/k1" 2>&1)
assert_contains "$out" "nothing written" "no at the question: nothing written"; assert_not_contains "$out" "can write" "...and no key was looked at"
assert_contains "$out" ".Decal/key" "...the key is in the list it showed"
# new --to stick:NAME: a tidy list of what's plugged in; a trailing / matches; no name is refused
mkdir -p "$DECAL_MEDIA/My Stick" "$DECAL_MEDIA/Other"
out=$("$REPO/decal" new decal-q --from empty --to stick:Nope 2>&1); assert_contains "$out" "(plugged in: My Stick, Other" "stick:NAME: the plugged-in sticks, comma-separated"
out=$("$REPO/decal" new decal-q --from empty --to "stick:$DECAL_MEDIA/Other/" 2>&1); assert_eq "$?" "0" "stick:PATH/ with a trailing slash"
out=$("$REPO/decal" new decal-q --from empty --to stick: 2>&1); assert_eq "$?" "1" "stick: with no name: refused"; assert_contains "$out" "stick:NAME needs a stick's name" "...says what it needs"
rm -rf "$DECAL_MEDIA/My Stick" "$DECAL_MEDIA/Other"
# the decal copy from a git checkout: its tracked files only, and -dirty when it has edits
GC="$T_TMP/gc"; git clone -q "$REPO" "$GC"; for f in decal install.sh lib usb modules; do cp -a "$REPO/$f" "$GC/"; done; echo junk > "$GC/lib/untracked-junk"; echo "# edit" >> "$GC/decal"
ln -s install.sh "$GC/lnk"; git -C "$GC" add lnk   # a tracked link: it must still point at its neighbour
"$GC/decal" usb --from "$P" --to "folder:$T_TMP/gcs" --yes >/dev/null 2>&1; assert_eq "$?" "0" "usb from a git checkout"
assert_contains "$(tar -tvzf "$T_TMP/gcs/.Decal/decal.tar.gz" | grep 'decal/lnk')" "-> install.sh" "...links keep their targets"
assert_not_contains "$(tar -tzf "$T_TMP/gcs/.Decal/decal.tar.gz")" "untracked-junk" "...untracked files left out"
assert_contains "$(cat "$T_TMP/gcs/.Decal/stick.conf")" "-dirty" "...the version says it has edits"
t_done
