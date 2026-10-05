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
# write new, then swap: files are replaced whole, never rewritten in place (a crash can't leave half a file)
printf 'old\n' > "$T_TMP/sw"; i=$(stat -c %i "$T_TMP/sw"); printf 'new\n' | swrite "$T_TMP/sw"
assert_eq "$(cat "$T_TMP/sw")" "new" "swrite: content"; assert_not_contains "$(stat -c %i "$T_TMP/sw")" "$i" "swrite: replaced whole"
assert_nofile "$T_TMP/sw.decal-new" "swrite: no leftover"
mkdir -p "$DECAL_ROOT/etc"; printf 'orig\n' > "$DECAL_ROOT/etc/swap.conf"; printf 'ours\n' | etc_write tst /etc/swap.conf
i=$(stat -c %i "$DECAL_ROOT/etc/swap.conf"); etc_restore tst /etc/swap.conf
assert_eq "$(cat "$DECAL_ROOT/etc/swap.conf")" "orig" "etc_restore: content"; assert_not_contains "$(stat -c %i "$DECAL_ROOT/etc/swap.conf")" "$i" "etc_restore: replaced whole"
# what a module put in place, recorded and taken away again (cursor, icons, gtk-theme, tools share these)
D="$T_TMP/themes"; R="$T_TMP/themes.rec"; mkdir -p "$D/Mine" "$T_TMP/src/A" "$T_TMP/src/Mine"; echo a > "$T_TMP/src/A/f"; echo yours > "$D/Mine/f"
install_owned "$D" A "$T_TMP/src/A" "$R"; assert_eq "$(cat "$D/A/f")" "a" "install_owned: copied"; rec_has "$R" A; assert_eq "$?" "0" "...and recorded"
out=$(install_owned "$D" Mine "$T_TMP/src/Mine" "$R" 2>&1); assert_contains "$out" "isn't from decal: left as is" "install_owned: yours left alone"
assert_eq "$(cat "$D/Mine/f")" "yours" "...untouched"; rec_has "$R" Mine; assert_eq "$?" "1" "...and not recorded"
echo a2 > "$T_TMP/src/A/f"; install_owned "$D" A "$T_TMP/src/A" "$R"; assert_eq "$(cat "$D/A/f")" "a2" "install_owned: ours replaced"
assert_eq "$(grep -c . "$R")" "1" "...recorded once"
rec_remove_all "$R" "$D"; assert_nofile "$D/A" "rec_remove_all: ours gone"; assert_file "$D/Mine/f" "...yours kept"; assert_nofile "$R" "...and the record"
# the settings a module changes: saved once (the first add), put back on remove
stub gsettings 'case $1 in get) echo "'"'"'was-$3'"'"'";; esac'
P="$T_TMP/x.prev"; gs_save "$P" org.gnome.desktop.interface cursor-theme cursor-size
assert_eq "$(cat "$P")" "cursor-theme='was-cursor-theme'"$'\n'"cursor-size='was-cursor-size'" "gs_save: the current values"
stub gsettings 'case $1 in get) echo "'"'"'later'"'"'";; esac'; gs_save "$P" org.gnome.desktop.interface cursor-theme
assert_contains "$(cat "$P")" "was-cursor-theme" "gs_save: only once (re-adding keeps the first values)"
LS_DRY_RUN=1 gs_save "$T_TMP/dry.prev" s k; assert_nofile "$T_TMP/dry.prev" "gs_save: nothing in a dry run"
: > "$STUBS/calls"; gs_restore "$P" org.gnome.desktop.interface
assert_contains "$(calls)" "gsettings set org.gnome.desktop.interface cursor-size 'was-cursor-size'" "gs_restore: put back"; assert_nofile "$P" "...and forgotten"
# stamp_theme: your theme, bundled when it's installed in your home; the system's own isn't carried
export STAMP_DIR="$T_TMP/stamp" STAMP_NOTES="$T_TMP/notes"; mkdir -p "$STAMP_DIR" "$T_TMP/hi/Mine"; echo x > "$T_TMP/hi/Mine/index.theme"
stub dconf 'echo "'"'"'Mine'"'"'"'
assert_eq "$(stamp_theme cursor cursor-theme "$T_TMP/nothere" "$T_TMP/hi")" $'[cursor]\nsource = "themes/cursor"\ntheme = "Mine"' "stamp_theme: the profile section"
assert_file "$STAMP_DIR/themes/cursor/Mine/index.theme" "...the theme bundled"; assert_contains "$(cat "$STAMP_NOTES")" "cursor: Mine (bundled" "...noted"
stub dconf 'echo "'"'"'Adwaita'"'"'"'
assert_eq "$(stamp_theme icons icon-theme "$T_TMP/hi")" "" "stamp_theme: a system theme isn't stamped"
assert_contains "$(cat "$STAMP_NOTES")" "icons: Adwaita (comes with the system: not stamped)" "...and says so"
# asking on the terminal (DECAL_TTY_IN/OUT stand in for it in tests)
DECAL_TTY_IN=/nonexistent have_tty; assert_eq "$?" "1" "have_tty: none"
printf 'two\n' > "$T_TMP/tty-in"; DECAL_TTY_IN="$T_TMP/tty-in" have_tty; assert_eq "$?" "0" "have_tty: there"
DECAL_TTY_IN="$T_TMP/tty-in" DECAL_TTY_OUT="$T_TMP/tty-out" tty_ask "Which? "; assert_eq "$REPLY" "two" "tty_ask: the answer in REPLY"
assert_eq "$(cat "$T_TMP/tty-out")" "Which? " "...after the question"
t_done
