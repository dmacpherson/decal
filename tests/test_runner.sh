#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export DECAL_MODULES_DIR="$REPO/tests/fixtures/modules" DECAL_PLATFORM=fedora
export LS_TEST_LOG="$T_TMP/log"; : > "$LS_TEST_LOG"
S="$REPO/decal"
export DECAL_PROFILE="$T_TMP/rprof"; mkdir -p "$DECAL_PROFILE"; : > "$DECAL_PROFILE/profile.toml"
# a module with a schema must be in the profile
out=$("$S" add eee-conf 2>&1); assert_eq "$?" "1" "not in profile rc"
assert_contains "$out" "eee-conf is not in your profile" "not in profile message"
out=$(DECAL_PROFILE="$T_TMP/none" "$S" add eee-conf 2>&1); assert_contains "$out" "no profile.toml" "add without any profile says so"
printf '[eee-conf]\nword = "yo"\n' > "$DECAL_PROFILE/profile.toml"
"$S" add eee-conf >/dev/null 2>&1; assert_contains "$(cat "$LS_TEST_LOG")" "eee add yo" "profile value reaches module"
printf '[eee-conf]\nwrod = "yo"\n' > "$DECAL_PROFILE/profile.toml"; : > "$LS_TEST_LOG"
out=$("$S" add aaa-ok 2>&1); assert_eq "$?" "1" "typo rejects the run"
assert_contains "$out" "unknown key 'wrod'" "typo message"; assert_eq "$(cat "$LS_TEST_LOG")" "" "no module ran on a bad profile"
printf '[eee-conf]\nword = "yo"\n' > "$DECAL_PROFILE/profile.toml"; : > "$LS_TEST_LOG"

out=$("$S" list 2>&1)
assert_contains "$out" "aaa-ok" "list shows module"; assert_contains "$out" "fixture that works" "list shows desc"

out=$("$S" add aaa-ok 2>&1); rc=$?
assert_eq "$rc" "0" "add ok rc"; assert_contains "$(cat "$LS_TEST_LOG")" "aaa add fedora" "platform loaded"
assert_contains "$out" "reboot required" "reboot notice"

# success without a reboot still exits 0 (and prints no reboot notice)
out=$("$S" add ddd-noreboot 2>&1); assert_eq "$?" "0" "no-reboot add rc"; assert_not_contains "$out" "reboot required" "no reboot notice"

# failing module stops the run, names it, and later modules don't run
: > "$LS_TEST_LOG"
out=$("$S" add all 2>&1); rc=$?
assert_eq "$rc" "1" "fail rc"; assert_contains "$out" "bbb-fail" "names failing module"
assert_not_contains "$(cat "$LS_TEST_LOG")" "bbb after false" "set -e inside module"
assert_not_contains "$(cat "$LS_TEST_LOG")" "ccc add" "stops after failure"

# remove all runs in reverse order
: > "$LS_TEST_LOG"; "$S" remove all >/dev/null 2>&1
assert_eq "$(tr '\n' ' ' < "$LS_TEST_LOG")" "eee remove ddd remove ccc remove bbb remove aaa remove " "reverse order"
# remove works from recorded state even when the profile is broken
cp "$DECAL_PROFILE/profile.toml" "$T_TMP/good.toml"; printf '[eee-conf\n' > "$DECAL_PROFILE/profile.toml"
: > "$LS_TEST_LOG"; out=$("$S" remove eee-conf 2>&1); assert_eq "$?" "0" "remove with a broken profile rc"
assert_eq "$(cat "$LS_TEST_LOG")" "eee remove" "remove ran from recorded state"
assert_contains "$out" "using defaults" "warns that the profile could not be read"
assert_not_contains "$("$S" status eee-conf 2>&1)" "error" "status with a broken profile still reports"
cp "$T_TMP/good.toml" "$DECAL_PROFILE/profile.toml"

# status and capture
out=$("$S" status 2>&1); assert_contains "$out" "aaa-ok" "status lists"; assert_contains "$out" "installed" "status value"
assert_eq "$("$S" capture aaa-ok 2>/dev/null)" "aaa capture" "capture"
out=$("$S" capture bbb-fail 2>&1); assert_eq "$?" "1" "capture unsupported rc"

# unknown module / command
out=$("$S" add nope 2>&1); assert_eq "$?" "1" "unknown module rc"; assert_contains "$out" "unknown module: nope" "unknown module msg"
out=$("$S" frob 2>&1); assert_eq "$?" "1" "unknown cmd rc"

# dry-run never calls sudo -v and never mutates
stub sudo; export DECAL_SUDO=sudo; : > "$STUBS/calls"
"$S" --dry-run add ccc-root >/dev/null 2>&1
assert_eq "$(calls)" "" "dry-run: no sudo calls at all"
assert_nofile "$LS_TEST_LOG.root" "dry-run: nothing touched"

# a real run asks sudo once, up front, for a root module
"$S" add ccc-root >/dev/null 2>&1
assert_contains "$(calls)" "sudo -v" "sudo -v up front"
# remove never asks up front: sudo only prompts if a module actually runs a privileged step
: > "$STUBS/calls"; "$S" remove ccc-root >/dev/null 2>&1
assert_not_contains "$(calls)" "sudo -v" "remove does not prompt up front"

# refuses to run as root (simulated)
out=$(DECAL_FAKE_EUID=0 "$S" list 2>&1); assert_eq "$?" "1" "root refused rc"
t_done
