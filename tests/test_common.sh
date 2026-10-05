#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup
source "$REPO/lib/common.sh"

# run / dry-run
out=$(LS_DRY_RUN=1 run echo hi 2>&1); assert_eq "$out" "[dry-run] echo hi" "run dry"
out=$(run echo hi 2>&1);              assert_eq "$out" "hi" "run real"

# sys_path prefixes LS_ROOT
assert_eq "$(sys_path /etc/x)" "$DECAL_ROOT/etc/x" "sys_path"

# etc_write on absent file records .absent; restore deletes it
printf 'new\n' | etc_write tst /etc/demo.conf
assert_eq "$(cat "$DECAL_ROOT/etc/demo.conf")" "new" "etc_write content"
assert_file "$DECAL_STATE/backups/tst/etc/demo.conf.absent" "absent marker"
etc_restore tst /etc/demo.conf
assert_nofile "$DECAL_ROOT/etc/demo.conf" "restored to absent"

# etc_write twice keeps the FIRST original
mkdir -p "$DECAL_ROOT/etc"; printf 'orig\n' > "$DECAL_ROOT/etc/b.conf"
printf 'one\n' | etc_write tst /etc/b.conf
printf 'two\n' | etc_write tst /etc/b.conf
etc_restore tst /etc/b.conf
assert_eq "$(cat "$DECAL_ROOT/etc/b.conf")" "orig" "first original wins"

# etc_seed_backup sets the original before first write
printf 'hand-edited\n' > "$DECAL_ROOT/etc/c.conf"
printf 'stock\n' | etc_seed_backup tst /etc/c.conf
printf 'ours\n' | etc_write tst /etc/c.conf
etc_restore tst /etc/c.conf
assert_eq "$(cat "$DECAL_ROOT/etc/c.conf")" "stock" "seeded original restored"

# restore with no backup is a silent no-op
out=$(etc_restore tst /etc/never.conf 2>&1); assert_eq "$?" "0" "restore no-op rc"; assert_eq "$out" "" "restore no-op quiet"

# dry-run etc_write does not create files
printf 'x\n' | LS_DRY_RUN=1 etc_write tst /etc/dry.conf 2>/dev/null
assert_nofile "$DECAL_ROOT/etc/dry.conf" "dry-run no write"

# need_reboot writes flag into LS_RUNTMP
export LS_RUNTMP="$T_TMP/rt"; mkdir -p "$LS_RUNTMP"; need_reboot
assert_file "$LS_RUNTMP/reboot" "reboot flag"
# tests never see the real home: everything a module does under $HOME or the XDG folders stays in the test's temp dir
for v in HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
  assert_contains "${!v:-unset}" "$T_TMP" "$v is inside the test's temp dir"
done
# names and paths from a profile, checked again where they're used (CLAUDE.md → Security)
for n in plymouth Bibata-Modern "Demo Spaced Icons" "dash-to-dock@micxgx.gmail.com"; do safe_name "$n"; assert_eq "$?" "0" "safe_name: $n"; done
for n in "" . .. ../x a/b -x "a
b"; do safe_name "$n"; assert_eq "$?" "1" "safe_name refuses: [$n]"; done
inside /usr/share/plymouth/themes /usr/share/plymouth/themes/angular; assert_eq "$?" "0" "inside: a theme folder"
inside /usr/share/plymouth/themes /usr/share/plymouth/themes/../../../etc; assert_eq "$?" "1" "inside: ../ refused"
inside /usr/share/plymouth/themes /usr/share/plymouth/themes; assert_eq "$?" "1" "inside: the folder itself isn't inside it"
mkdir -p "$T_TMP/in"; ln -s /etc "$T_TMP/in/out"; inside "$T_TMP/in" "$T_TMP/in/out/passwd"; assert_eq "$?" "1" "inside: a link out refused"
t_done
