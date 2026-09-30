#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; source "$REPO/lib/common.sh"; LS_REPO="$REPO"
export DECAL_PLATFORM=fedora; source "$REPO/lib/platform.sh"; platform_load
export LS_RUNTMP="$T_TMP/rt"; mkdir -p "$LS_RUNTMP"

# rpm: only "plymouth" is present
stub rpm 'for a; do [[ $a == plymouth ]] && exit 0; done; exit 1'
stub dnf; stub dracut
pkg_install ply plymouth plymouth-script-plugin
assert_contains "$(calls)" "dnf install -y plymouth-plugin-script" "maps + installs only missing"
assert_not_contains "$(calls)" "dnf install -y plymouth " "skips present"
assert_eq "$(cat "$DECAL_STATE/pkgs/ply")" "plymouth-plugin-script" "records owner pkgs"

# another owner also recorded it -> pkg_remove of first owner keeps it
printf 'plymouth-plugin-script\n' > "$DECAL_STATE/pkgs/other"
stub rpm 'exit 0'; : > "$STUBS/calls"
pkg_remove ply
assert_not_contains "$(calls)" "dnf remove" "shared pkg kept"
assert_nofile "$DECAL_STATE/pkgs/ply" "owner record removed"
rm "$DECAL_STATE/pkgs/other"

# pkg_remove with no record: no-op
: > "$STUBS/calls"; pkg_remove nobody; assert_eq "$(calls)" "" "remove no-op"

# files_install / files_installed / files_remove
src="$T_TMP/src"; mkdir -p "$src/sub"; echo a > "$src/a.txt"; echo b > "$src/sub/b.txt"
files_install thm "$src" /usr/share/demo/thm
assert_file "$DECAL_ROOT/usr/share/demo/thm/sub/b.txt" "copied"
files_installed thm; assert_eq "$?" "0" "installed yes"
assert_eq "$(head -1 "$DECAL_STATE/files/thm.list")" "/usr/share/demo/thm" "manifest dest"
files_remove thm
assert_nofile "$DECAL_ROOT/usr/share/demo/thm" "dest dir removed"
files_installed thm; assert_eq "$?" "1" "installed no"
files_remove thm; assert_eq "$?" "0" "remove twice no-op"
# installing to another destination (a different theme) first removes the old files
files_install thm "$src" /usr/share/demo/old; files_install thm "$src" /usr/share/demo/new
assert_nofile "$DECAL_ROOT/usr/share/demo/old" "old destination removed when it changes"
assert_file "$DECAL_ROOT/usr/share/demo/new/a.txt" "new destination installed"; files_remove thm

# initramfs refcount + skip env + reboot flag
: > "$STUBS/calls"
initramfs_require ply; assert_contains "$(calls)" "dracut -f --regenerate-all" "rebuild on require"
: > "$STUBS/calls"; initramfs_require ply; assert_eq "$(calls)" "" "require again with nothing changed: no rebuild"
: > "$STUBS/calls"; initramfs_dirty; initramfs_require ply; assert_contains "$(calls)" "dracut -f --regenerate-all" "rebuild after a change"
assert_file "$LS_RUNTMP/reboot" "reboot flagged"
: > "$STUBS/calls"; DECAL_SKIP_INITRAMFS=1 initramfs_release ply
assert_eq "$(calls)" "" "skip env"; assert_nofile "$DECAL_STATE/initramfs/ply" "marker gone"
: > "$STUBS/calls"; initramfs_release ply; assert_eq "$(calls)" "" "release without marker no-op"

# debian map: plymouth-script-plugin provided by plymouth
export DECAL_PLATFORM=debian; platform_load
assert_eq "$(_pkg_name plymouth-script-plugin)" "" "debian map empty"
assert_eq "$(_pkg_name flatpak)" "flatpak" "identity"
# debian: purge (keeps no conffiles) exactly what we installed, plus only OUR deps that apt says are now unneeded
export DECAL_PLATFORM=debian; platform_load; : > "$STUBS/calls"
printf 'base-files\noldkernel\n' > "$STUBS/installed"
stub dpkg-query 'db="$STUBS/installed"; if [[ $2 == *Status* ]]; then grep -qx "$3" "$db" && echo "install ok installed"; else cat "$db"; fi'
stub apt-get 'db="$STUBS/installed"; case " $* " in *" install "*) for a; do [[ $a == -* || $a == install || $a == env || $a == *=* ]] || echo "$a" >> "$db"; done; echo libdep >> "$db";; *" -s autoremove "*) echo "Remv libdep [1.0]"; echo "Remv oldkernel [6.1]";; *" purge "*) for a; do [[ $a == -* ]] && continue; grep -vxF -e "$a" "$db" > "$db.t"; mv "$db.t" "$db"; done;; esac'
pkg_install deb plymouth
assert_eq "$(cat "$DECAL_STATE/pkgs/deb")" "plymouth" "records requested package"
assert_eq "$(cat "$DECAL_STATE/pkgs/deb.deps" 2>/dev/null)" "libdep" "records deps our install pulled in"
: > "$STUBS/calls"; pkg_remove deb
assert_contains "$(calls)" "apt-get purge -y plymouth" "purges what we installed"
assert_contains "$(calls)" "apt-get purge -y libdep" "purges our now-unneeded deps"
assert_not_contains "$(calls)" "oldkernel" "never touches other orphans"
assert_not_contains "$(calls)" "--auto-remove" "no system-wide autoremove"
assert_nofile "$DECAL_STATE/pkgs/deb.deps" "deps record cleared"
export DECAL_PLATFORM=arch; platform_load
assert_eq "$(_pkg_name plymouth-script-plugin)" "" "arch map empty"
# transaction hooks (unmount around package transactions)
export DECAL_PLATFORM=debian; platform_load; : > "$STUBS/calls"
txn_hooks_add demo "/x/helper umount" "/x/helper mount"
f="$DECAL_ROOT/etc/apt/apt.conf.d/80decal-demo"
assert_contains "$(cat "$f")" 'DPkg::Pre-Invoke {"/x/helper umount || true";};' "apt pre hook"
assert_contains "$(cat "$f")" 'DPkg::Post-Invoke {"/x/helper mount || true";};' "apt post hook"
txn_hooks_remove demo; assert_nofile "$f" "apt hook removed"
export DECAL_PLATFORM=arch; platform_load
txn_hooks_add demo "/x/helper umount" "/x/helper mount"
assert_contains "$(cat "$DECAL_ROOT/etc/pacman.d/hooks/80-decal-demo-pre.hook")" "When = PreTransaction" "pacman pre hook"
assert_contains "$(cat "$DECAL_ROOT/etc/pacman.d/hooks/80-decal-demo-post.hook")" "Exec = /x/helper mount" "pacman post hook"
txn_hooks_remove demo; assert_nofile "$DECAL_ROOT/etc/pacman.d/hooks/80-decal-demo-pre.hook" "pacman hooks removed"
export DECAL_PLATFORM=fedora; platform_load; stub rpm 'exit 1'; stub dnf; : > "$STUBS/calls"
stub dnf5; txn_hooks_add demo "/x/helper umount" "/x/helper mount"
assert_contains "$(calls)" "dnf install -y libdnf5-plugin-actions" "actions plugin installed"
assert_eq "$(cat "$DECAL_ROOT/etc/dnf/libdnf5-plugins/actions.d/decal-demo.actions")" $'pre_transaction::::/x/helper umount\npost_transaction::::/x/helper mount' "dnf5 actions"
txn_hooks_remove demo; assert_nofile "$DECAL_ROOT/etc/dnf/libdnf5-plugins/actions.d/decal-demo.actions" "dnf5 actions removed"
DECAL_NO_DNF5=1 txn_hooks_add demo2 a b 2>/dev/null; assert_eq "$?" "1" "dnf4-only system: unsupported"
export DECAL_PLATFORM=fedora-atomic; platform_load; txn_hooks_add demo a b; assert_eq "$?" "0" "atomic: no-op success"
# pkg_uninstall: only the named packages, never a cascade
export DECAL_PLATFORM=fedora; platform_load; : > "$STUBS/calls"
stub rpm 'case "$*" in "-q --quiet firefox"|"-q --quiet vim-minimal") exit 0;; "-e --test firefox") exit 0;; "-e --test vim-minimal") echo "error: vim-minimal is needed by sudo"; exit 1;; esac; exit 1'
pkg_uninstall tst firefox nothere
assert_contains "$(calls)" "dnf remove -y --setopt=clean_requirements_on_remove=False firefox" "removes a present, unneeded package (no autoremove)"
assert_not_contains "$(grep "^dnf" "$STUBS/calls")" "nothere" "absent packages ignored"
assert_eq "$(cat "$DECAL_STATE/pkgs/tst.removed")" "firefox" "recorded"
out=$( (pkg_uninstall tst vim-minimal) 2>&1 ); assert_eq "$?" "1" "refuses when others depend on it"
assert_contains "$out" "needed by sudo" "shows why"
: > "$STUBS/calls"; pkg_restore tst
assert_contains "$(calls)" "dnf install -y firefox" "restore reinstalls"; assert_nofile "$DECAL_STATE/pkgs/tst.removed" "record cleared"
# debian: extra Remv lines -> refused
export DECAL_PLATFORM=debian; platform_load
stub dpkg-query 'echo "install ok installed"'
stub apt-get 'case "$*" in *"-s remove libfoo"*) echo "Remv libfoo [1]"; echo "Remv app-using-libfoo [2]";; *"-s remove bar"*) echo "Remv bar [1]";; esac'
out=$( (pkg_uninstall tst libfoo) 2>&1 ); assert_eq "$?" "1" "debian refuses a cascade"
assert_contains "$out" "app-using-libfoo" "lists the extra package"
: > "$STUBS/calls"; pkg_uninstall tst bar; assert_contains "$(calls)" "apt-get remove -y bar" "debian removes a leaf package (keeps its config files)"
stub apt-get 'case "$*" in *"-s remove libc6"*) echo "The following packages have unmet dependencies:"; exit 100;; esac'
out=$( (set -e; pkg_uninstall tst libc6) 2>&1 ); assert_eq "$?" "1" "debian refuses when apt's simulation fails"
assert_contains "$out" "unmet dependencies" "shows apt's reason"
pkg_restore tst >/dev/null 2>&1
# a failed removal is an error and is not recorded as removed
export DECAL_PLATFORM=fedora; platform_load
stub rpm 'case "$*" in "-q --quiet firefox") exit 0;; "-e --test firefox") exit 0;; esac; exit 1'
stub dnf 'exit 1'
out=$( (set -e; pkg_uninstall tst firefox) 2>&1 ); assert_eq "$?" "1" "failed removal fails"
assert_nofile "$DECAL_STATE/pkgs/tst.removed" "failed removal not recorded"
# arch: plain -R (no recursive removal of dependencies)
export DECAL_PLATFORM=arch; platform_load; stub pacman 'exit 0'; : > "$STUBS/calls"
pkg_uninstall tst firefox; assert_contains "$(calls)" "pacman -R --noconfirm firefox" "arch removes only the named package"
pkg_restore tst >/dev/null 2>&1
t_done
