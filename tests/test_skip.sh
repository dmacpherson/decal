#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
export DECAL_MODULES_DIR="$REPO/tests/fixtures/modules-skip" DECAL_PLATFORM=fedora LS_TEST_LOG="$T_TMP/log"
export DECAL_PROFILE="$T_TMP/prof"; mkdir -p "$DECAL_PROFILE"; echo one > "$DECAL_PROFILE/f.txt"
printf '[sk]\nword = "a"\nfile = "f.txt"\n' > "$DECAL_PROFILE/profile.toml"
S="$REPO/decal"; runs() { grep -c '^sk add' "$LS_TEST_LOG" 2>/dev/null || true; }
"$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "1" "first add runs"
out=$("$S" add sk 2>&1); assert_eq "$(runs)" "1" "applied and unchanged: skipped (nothing downloaded or run)"
assert_contains "$out" "up to date" "says it's up to date"
sed -i 's/^word = "a"/word = "b"/' "$DECAL_PROFILE/profile.toml"
"$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "2" "a changed setting re-applies"
echo two > "$DECAL_PROFILE/f.txt"
"$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "3" "a changed file the settings point to re-applies"
# a file referenced from a table (e.g. [gnome-extensions.files] "a/b.conf" = "x.conf") counts too
echo t1 > "$DECAL_PROFILE/t.conf"; printf '[sk.files]\n"cfg/dir/t.conf" = "t.conf"\n' >> "$DECAL_PROFILE/profile.toml"
"$S" add sk >/dev/null 2>&1; n=$(runs); echo t2 > "$DECAL_PROFILE/t.conf"
"$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "$((n + 1))" "a changed file referenced from a table re-applies"
rm -f "$DECAL_USER_STATE/sk.done"
n=$(runs); "$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "$((n + 1))" "status says not installed (e.g. changed by hand): re-applies"
n=$(runs); "$S" --force add sk >/dev/null 2>&1; assert_eq "$(runs)" "$((n + 1))" "--force applies anyway"
"$S" --dry-run add sk >/dev/null 2>&1; out=$("$S" --dry-run add sk 2>&1); assert_contains "$out" "up to date" "dry-run shows the skip too"
n=$(runs); "$S" remove sk >/dev/null 2>&1; "$S" add sk >/dev/null 2>&1; assert_eq "$(runs)" "$((n + 1))" "after remove, add runs again"
"$S" apply "$DECAL_PROFILE" >/dev/null 2>&1; assert_eq "$(runs)" "$((n + 1))" "apply skips up-to-date modules too"
t_done
