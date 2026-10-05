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
stub curl 'out=""; w=""; for a; do case $prev in -o) out=$a;; -w) w=$a;; esac; prev=$a; done
case ${@: -1} in *repos/me/p/tarball*) cp '"$T_TMP"'/gh.tar.gz "$out"; [ -z "$w" ] || printf 200;; *) [ -z "$w" ] || printf 404; exit 22;; esac'
out=$(DECAL_STICK_KEY=r3ad GITHUB_TOKEN=s3cret U --from me/p --how saved-key --to "$T" --yes); assert_eq "$?" "0" "GitHub + saved key"
assert_contains "$(cat "$T/.Decal/stick.conf")" "profile=github:me/p" "stick.conf: the repo"; assert_contains "$(cat "$T/.Decal/stick.conf")" "key=saved" "...key saved"
assert_eq "$(cat "$T/.Decal/key")" "r3ad" "the given read key, not GITHUB_TOKEN"
assert_eq "$(grep -rl s3cret "$T" | wc -l)" "0" "GITHUB_TOKEN never written to the stick"
U --from me/p --how sign-in --to "$T" --yes >/dev/null; assert_nofile "$T/.Decal/key" "sign-in: no key on the stick"
assert_contains "$(cat "$T/.Decal/stick.conf")" "key=ask" "...stick.conf says ask"
# no terminal, no --yes: stops before writing
rm -rf "$T"; mkdir -p "$T"
out=$(setsid -w "$REPO/decal" usb --from "$P" --to "$T" 2>&1 < /dev/null); assert_eq "$?" "1" "no terminal, no --yes: stops"
assert_contains "$out" "--yes" "...says how to go on"; assert_nofile "$T/.Decal" "...nothing written"
# a folder
U --from "$P" --to "folder:$T_TMP/usbfolder" --yes >/dev/null; assert_file "$T_TMP/usbfolder/Decal" "folder target"
# public check
DECAL_GITHUB_API=http://127.0.0.1:9 python3 "$REPO/lib/source.py" public github:me/p >/dev/null 2>&1; assert_eq "$?" "1" "public: GitHub unreachable → not known public"
t_done
