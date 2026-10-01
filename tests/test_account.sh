#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora
# fake AccountsService: IconFile is kept in $STUBS/iconfile; SetIconFile copies the image like the daemon does
# (an empty name clears it back to the default ~/.face)
ICONS="$T_TMP/icons"; mkdir -p "$ICONS"; echo "$HOME/.face" > "$STUBS/iconfile"
stub busctl 'case "$*" in
  *FindUserByName*) echo "o \"/org/freedesktop/Accounts/User1000\"";;
  *get-property*IconFile*) echo "s \"$(cat "$STUBS/iconfile")\"";;
  *SetIconFile*) f="${@: -1}"; if [ -n "$f" ] && [ "$(readlink -f "$f")" != "$f" ]; then echo "file $f is not a regular file" >&2; exit 1; fi   # like the daemon
                 if [ -z "$f" ]; then rm -f "'"$ICONS"'/me"; echo "$HOME/.face" > "$STUBS/iconfile";
                 else cp "$f" "'"$ICONS"'/me"; echo "'"$ICONS"'/me" > "$STUBS/iconfile"; fi;;
esac'
echo picture-1 > "$PROFILE_DIR/me.png"; printf '[account]\npicture = "me.png"\n' >> "$PROFILE_DIR/profile.toml"
# the active profile is normally a link (~/.config/decal/profile -> your clone): the daemon rejects paths through it
ln -s "$PROFILE_DIR" "$T_TMP/linked-profile"; REAL="$PROFILE_DIR"; PROFILE_DIR="$T_TMP/linked-profile"
run_mod() { mod_run account "module_$1"; }
PREV="$DECAL_USER_STATE/account-picture.prev"

assert_eq "$(run_mod status)" "not-installed" "before: not set"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "SetIconFile s $REAL/me.png" "picture handed to AccountsService by its real path (no sudo)"
assert_eq "$(cat "$ICONS/me")" "picture-1" "account picture is the profile's"
assert_eq "$(run_mod status)" "installed" "status after add"
assert_file "$PREV" "previous picture recorded"; assert_nofile "$PREV/picture" "(there was none)"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "SetIconFile" "already set: not set again"
echo picture-2 > "$PROFILE_DIR/me.png"
assert_eq "$(run_mod status)" "not-installed" "a changed picture in the profile shows up"
run_mod add >/dev/null 2>&1; assert_eq "$(cat "$ICONS/me")" "picture-2" "and is set on the next add"
: > "$STUBS/calls"; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "SetIconFile s " "remove with no previous picture clears it"
assert_eq "$(cat "$STUBS/iconfile")" "$HOME/.face" "back to the default"; assert_nofile "$PREV" "record removed"
# someone who had their own picture gets it back on remove
echo my-old-picture > "$ICONS/me"; echo "$ICONS/me" > "$STUBS/iconfile"
run_mod add >/dev/null 2>&1; assert_eq "$(cat "$PREV/picture")" "my-old-picture" "their own picture kept"
run_mod remove >/dev/null 2>&1; assert_eq "$(cat "$ICONS/me")" "my-old-picture" "and restored on remove"
# a picture that isn't there is an error, not a silent no-op
rm "$PROFILE_DIR/me.png"; out=$(run_mod add 2>&1); assert_eq "$([[ $? != 0 ]] && echo fails)" "fails" "missing picture fails (the profile check catches it)"
assert_contains "$out" "me.png" "and names the file"
t_done
