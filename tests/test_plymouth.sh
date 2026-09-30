#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
export DECAL_PLATFORM=fedora-atomic DECAL_SKIP_INITRAMFS=1
mkdir -p "$DECAL_ROOT/etc/plymouth" "$DECAL_ROOT/usr/etc/plymouth"
printf '[Daemon]\nTheme=angular\n' > "$DECAL_ROOT/etc/plymouth/plymouthd.conf"      # hand-edited
printf '# Administrator customizations go in this file\n#[Daemon]\n#Theme=fade-in\n' > "$DECAL_ROOT/usr/etc/plymouth/plymouthd.conf"
mod_run_pre() {
  pkg_install() { echo "pkg_install $*" >> "$STUBS/calls"; }; pkg_remove() { echo "pkg_remove $*" >> "$STUBS/calls"; }
  files_install() { echo "files_install $* REPLACES=${FILES_REPLACES:-}" >> "$STUBS/calls"; }
  files_remove() { echo "files_remove $*" >> "$STUBS/calls"; }; files_installed() { return 0; }
}
run_mod() { mod_run plymouth "module_$1"; }
# hand-made install present, nothing managed yet -> tell the user to adopt it
mkdir -p "$DECAL_ROOT/usr/share/plymouth/themes/angular"
assert_eq "$( ( mod_run_pre() { files_installed() { return 1; }; }; mod_run plymouth module_status ) 2>/dev/null)" "not-installed (theme present but unmanaged; run add to adopt)" "unmanaged hand install"
run_mod add 2>/dev/null
assert_contains "$(calls)" "pkg_install plymouth plymouth plymouth-script-plugin" "packages"
assert_contains "$(calls)" "files_install plymouth $PROFILE_DIR/demo-plymouth/angular /usr/share/plymouth/themes/angular REPLACES=plymouth-theme-angular" "files from the fetched source + adoption"
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
t_done
