#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
unset DISPLAY WAYLAND_DISPLAY GITHUB_TOKEN GH_TOKEN; stub gh 'exit 1'
export DECAL_MEDIA="$T_TMP/media" DECAL_PROFILE_HOME="$T_TMP/active"; mkdir -p "$DECAL_MEDIA"
M="$T_TMP/mods"; mkdir -p "$M/live"; echo '{"keys": {"word": {"type": "string", "default": "x"}}}' > "$M/live/schema.json"
printf 'module_stamp() { printf "[live]\\nword = \\"here\\"\\n"; }\n' > "$M/live/module.sh"
export DECAL_MODULES_DIR="$M" DECAL_PLATFORM=fedora
N() { "$REPO/decal" new "$@" 2>&1; }
x() { rm -rf "$T_TMP/x"; mkdir -p "$T_TMP/x"; tar -xzf "$1" -C "$T_TMP/x"; }

# from this machine, to a file
out=$(N decal-a --to file); assert_eq "$?" "0" "this machine → file"; assert_contains "$out" "new profile: $HOME/decal-a.tar.gz" "...says where"
x "$HOME/decal-a.tar.gz"; assert_contains "$(cat "$T_TMP/x/profile.toml")" 'word = "here"' "...the stamp is in it"
assert_contains "$(cat "$T_TMP/x/README.md")" "# decal-a" "...a README naming it"
assert_nofile "$T_TMP/x/.decal-stamp" "...no stamp marker in a file"
out=$(N decal-a --to file); assert_eq "$?" "1" "never overwrites"; assert_contains "$out" "already exists: use decal stamp to update it" "...says what to do"
# empty, to a chosen path
out=$(N decal-b --from empty --to "file:$T_TMP/b.tgz"); assert_eq "$?" "0" "empty → file:PATH"
x "$T_TMP/b.tgz"; assert_eq "$(grep -cv '^\s*#\|^\s*$' "$T_TMP/x/profile.toml")" "0" "empty: every line a comment"
python3 "$REPO/lib/profile.py" check --profile "$T_TMP/x" --modules "$M"; assert_eq "$?" "0" "empty: a valid profile"
# a copy of another profile, to the stick
mkdir -p "$T_TMP/src"; printf '[live]\nword = "copied"\n' > "$T_TMP/src/profile.toml"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "1" "no stick plugged in: refused"; assert_contains "$out" "plug in a USB stick" "...says so"
mkdir -p "$DECAL_MEDIA/Ventoy"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "0" "copy → stick"
assert_contains "$(cat "$DECAL_MEDIA/Ventoy/.Decal/profile/profile.toml")" 'word = "copied"' "...copied"
assert_file "$DECAL_MEDIA/Ventoy/.Decal/profile/.decal-stamp" "...stamp can update it later"
assert_contains "$(cat "$DECAL_MEDIA/Ventoy/.Decal/profile/README.md")" "copied from $T_TMP/src" "...README says where it came from"
out=$(N decal-c --from "$T_TMP/src" --to stick); assert_eq "$?" "1" "stick profile exists: refused"
# several sticks: asks which
mkdir -p "$DECAL_MEDIA/Other"; printf '1\n' > "$T_TMP/k2"
out=$(DECAL_TTY_IN="$T_TMP/k2" DECAL_TTY_OUT="$T_TMP/scr2" N decal-g --from empty --to stick); assert_eq "$?" "0" "two sticks: asked which"
assert_contains "$(cat "$T_TMP/scr2")" "2) Ventoy" "...listed them"
assert_file "$DECAL_MEDIA/Other/.Decal/profile/profile.toml" "...and used the one chosen"
# several sticks, the way past the question: --to stick:NAME (audit batch 3)
out=$(N decal-h --from empty --to stick 2>&1 < /dev/null); assert_eq "$?" "1" "two sticks, no terminal: stops"
assert_contains "$out" "--to stick:NAME" "...says how to pick one"
rm -rf "$DECAL_MEDIA/Other/.Decal"
out=$(N decal-h --from empty --to stick:Other < /dev/null); assert_eq "$?" "0" "--to stick:Other: no question"
assert_file "$DECAL_MEDIA/Other/.Decal/profile/profile.toml" "...on that stick"
out=$(N decal-h --from empty --to stick:Nope); assert_eq "$?" "1" "--to stick:NAME that isn't plugged in: refused"
assert_contains "$out" "no USB stick named Nope" "...says so"
rm -rf "$DECAL_MEDIA/Other"
# --use makes it active (nothing applied)
out=$(N decal-d --from "$T_TMP/src" --to file --use); assert_eq "$?" "0" "--use"
assert_eq "$(cat "$DECAL_PROFILE_HOME/.decal-source")" "$HOME/decal-d.tar.gz" "...the new one is active"

# to GitHub: signs in with the write app when there's no key; a repo that exists is refused
G="$T_TMP/gh"; mkdir -p "$G"; echo s3cret > "$G/token"; echo tester/decal-taken > "$G/seed"; echo ok > "$G/device_script"
fake_github "$G"; GHPID=$FAKE_PID
export DECAL_GITHUB_APP_WRITE=Iv-write:decal-write
printf '1\n' > "$T_TMP/keys"
out=$(DECAL_TTY_IN="$T_TMP/keys" DECAL_TTY_OUT="$T_TMP/screen" N decal-e --from empty); assert_eq "$?" "0" "empty → GitHub (signed in)"
assert_contains "$out" "new profile: github:tester/decal-e" "...says where"
assert_contains "$(cat "$G/device_log")" "client_id=Iv-write" "...with the write app"
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$G/tester_decal-e.json")" "True" "...private"
assert_contains "$(cat "$G/topics.log")" "tester/decal-e decal-profile" "...tagged as a profile"
out=$(GITHUB_TOKEN=s3cret N decal-taken --from empty); assert_eq "$?" "1" "an existing repo: refused"
assert_contains "$out" "github:tester/decal-taken already exists" "...says so"
GITHUB_TOKEN=s3cret N decal-f --from empty --public >/dev/null
assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["private"])' "$G/tester_decal-f.json")" "False" "--public"
out=$(N 'bad name' --from empty --to file); assert_eq "$?" "1" "a name with a space: refused"
kill "$GHPID" 2>/dev/null
t_done
