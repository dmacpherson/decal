#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora-atomic DECAL_SKIP_INITRAMFS=1
mkdir -p "$DECAL_ROOT/etc/plymouth" "$DECAL_ROOT/usr/etc/plymouth"
printf '[Daemon]\nTheme=angular\n' > "$DECAL_ROOT/etc/plymouth/plymouthd.conf"      # hand-edited
printf '# Administrator customizations go in this file\n#[Daemon]\n#Theme=fade-in\n' > "$DECAL_ROOT/usr/etc/plymouth/plymouthd.conf"
mod_run_pre() {
  pkg_install() { echo "pkg_install $*" >> "$STUBS/calls"; }; pkg_remove() { echo "pkg_remove $*" >> "$STUBS/calls"; }
  files_install() { echo "files_install $* REPLACES=${FILES_REPLACES:-} REQUIRES=${FILES_REQUIRES:-}" >> "$STUBS/calls"; }
  files_remove() { echo "files_remove $*" >> "$STUBS/calls"; }; files_installed() { return 0; }
}
run_mod() { mod_run plymouth "module_$1"; }
# hand-made install present, nothing managed yet -> tell the user to adopt it
mkdir -p "$DECAL_ROOT/usr/share/plymouth/themes/angular"
assert_eq "$( ( mod_run_pre() { files_installed() { return 1; }; }; mod_run plymouth module_status ) 2>/dev/null)" "not-installed (theme present but unmanaged; run add to adopt)" "unmanaged hand install"
run_mod add 2>/dev/null
assert_contains "$(calls)" "pkg_install plymouth plymouth plymouth-script-plugin" "packages"
assert_contains "$(calls)" "files_install plymouth $PROFILE_DIR/demo-plymouth/angular /usr/share/plymouth/themes/angular REPLACES=plymouth-theme-angular REQUIRES=plymouth-plugin-script" "files from the fetched source + adoption + script plugin kept"
assert_eq "$(cat "$DECAL_ROOT/etc/plymouth/plymouthd.conf")" $'[Daemon]\nTheme=angular' "conf written"
assert_eq "$(head -1 "$DECAL_STATE/initramfs.prior")" "0" "adopting the hand install records regeneration as previously off"
stub rpm 'exit 1'; assert_eq "$(run_mod status 2>/dev/null)" "installed (reboot pending)" "status before reboot"
stub rpm 'exit 0'; assert_eq "$(run_mod status 2>/dev/null)" "installed" "status after reboot"
run_mod remove 2>/dev/null
assert_contains "$(cat "$DECAL_ROOT/etc/plymouth/plymouthd.conf")" "#Theme=fade-in" "restored STOCK conf, not hand-edited"
sed -i 's/^theme = "angular"/theme = "nope"/' "$PROFILE_DIR/profile.toml"
out=$(run_mod add 2>&1); assert_contains "$out" "plymouth theme 'nope' not found" "missing theme: clear error"
# Debian: the alternative registered at add time is the one removed, even after the section is deleted
cp -r "$PROFILE_DIR/demo-plymouth/angular" "$PROFILE_DIR/demo-plymouth/second"   # not the schema default
sed -i 's/^theme = "nope"/theme = "second"/' "$PROFILE_DIR/profile.toml"
stub update-alternatives; stub plymouth-set-default-theme 'echo text'; : > "$STUBS/calls"
DECAL_PLATFORM=debian run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "update-alternatives --set default.plymouth /usr/share/plymouth/themes/second/second.plymouth" "debian: alternative set"
python3 - "$PROFILE_DIR/profile.toml" <<'EOF'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[plymouth\]\n.*?(?=^\[|\Z)","",s); open(p,'w').write(s)
EOF
: > "$STUBS/calls"; DECAL_PLATFORM=debian run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "update-alternatives --remove default.plymouth /usr/share/plymouth/themes/second/second.plymouth" "debian: recorded alternative removed without the section"
# the initramfs is only rebuilt when something in it changed
export LS_RUNTMP="$T_TMP/rt"; mkdir -p "$LS_RUNTMP"
sed -i 's/^theme = "[a-z]*"$/theme = "angular"/' "$PROFILE_DIR/profile.toml"; grep -q '^\[plymouth\]' "$PROFILE_DIR/profile.toml" || printf '[plymouth]\nsource = "demo-plymouth"\npath = ""\ntheme = "angular"\n' >> "$PROFILE_DIR/profile.toml"
dirty_run() { rm -f "$LS_RUNTMP/initramfs-dirty"; : > "$STUBS/calls"
  ( mod_run_pre() { pkg_install() { :; }; files_install() { :; }; files_installed() { return 0; }
      initramfs_require() { echo "require dirty=$([[ -e $LS_RUNTMP/initramfs-dirty ]] && echo 1 || echo 0)" >> "$STUBS/calls"; }; }
    DECAL_PLATFORM=$1 mod_run plymouth module_add ) >/dev/null 2>&1; grep -o 'dirty=[01]' "$STUBS/calls"; }
printf '[Daemon]\nTheme=angular\n' > "$DECAL_ROOT/etc/plymouth/plymouthd.conf"
assert_eq "$(dirty_run fedora-atomic)" "dirty=0" "atomic, config unchanged: no rebuild"
printf '[Daemon]\nTheme=spinner\n' > "$DECAL_ROOT/etc/plymouth/plymouthd.conf"
assert_eq "$(dirty_run fedora-atomic)" "dirty=1" "config changed: rebuild"
stub rpm 'exit 0'   # mutable: packages present
cp -r "$PROFILE_DIR/demo-plymouth/angular" "$DECAL_ROOT/usr/share/plymouth/themes/"
assert_eq "$(dirty_run fedora)" "dirty=0" "mutable, same files and config: no rebuild"
echo changed >> "$PROFILE_DIR/demo-plymouth/angular/angular.script"
assert_eq "$(dirty_run fedora)" "dirty=1" "mutable, theme files changed: rebuild"
# adi1090x-style themes position the animation once at start: decal installs a copy that re-centres every frame
# (a screen that changes size during boot left it in a corner); other themes are installed as they are
printf '%s\n' 'flyingman_sprite = Sprite();' 'flyingman_sprite.SetX(Window.GetX() + (Window.GetWidth(0) / 2 - flyingman_image[0].GetWidth() / 2));' \
  'fun refresh_callback () { progress++; }' 'Plymouth.SetRefreshFunction (refresh_callback);' > "$PROFILE_DIR/demo-plymouth/angular/angular.script"
orig=$(cat "$PROFILE_DIR/demo-plymouth/angular/angular.script")
: > "$STUBS/calls"
( mod_run_pre() { pkg_install() { :; }; files_installed() { return 0; }; initramfs_require() { :; }
    files_install() { echo "files_install $2" >> "$STUBS/calls"; cp -a "$2" "$T_TMP/installed"; }; }
  DECAL_PLATFORM=fedora mod_run plymouth module_add ) >/dev/null 2>&1
assert_not_contains "$(calls)" "files_install $PROFILE_DIR/demo-plymouth/angular" "adi theme: a patched copy is installed, not the source"
assert_contains "$(cat "$T_TMP/installed/angular.script")" "Plymouth.SetRefreshFunction (decal_refresh_callback);" "re-centring refresh added"
assert_contains "$(cat "$T_TMP/installed/angular.script")" "$orig" "the theme's own script kept"
assert_file "$T_TMP/installed/angular.plymouth" "the rest of the theme copied"
assert_eq "$(cat "$PROFILE_DIR/demo-plymouth/angular/angular.script")" "$orig" "the fetched source is untouched"
t_done
