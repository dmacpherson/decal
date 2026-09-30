#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; source "$REPO/lib/common.sh"; LS_REPO="$REPO"
export DECAL_PLATFORM=fedora-atomic DECAL_RPM_DIR="$T_TMP/rpms"
source "$REPO/lib/platform.sh"; platform_load
export LS_RUNTMP="$T_TMP/rt"; mkdir -p "$LS_RUNTMP"
JSON="$T_TMP/status.json"
_ostree_json() { cat "$JSON"; }   # override the probe
cat > "$JSON" <<'EOF'
{"deployments":[{"booted":true,"osname":"default","checksum":"abc","serial":0,
 "requested-packages":["htop"],"requested-local-packages":["plymouth-theme-angular-1.0-1.fc44.noarch"],
 "regenerate-initramfs":false}]}
EOF
assert_eq "$(_requested | sort | tr '\n' ' ')" "htop plymouth-theme-angular " "requested names (local NEVRA stripped)"
assert_eq "$(_pending_root)" "" "no pending when deployment 0 is booted"

# files_install builds via container and layers, replacing the manual package in ONE transaction
stub rpm-ostree; stub podman 'echo "+ CFLAGS=-O2 noise"; echo "[3/65] Installing noise" >&2; mkdir -p "$DECAL_RPM_DIR"; touch "$DECAL_RPM_DIR/$(cat "$STUBS/want")"'
src="$T_TMP/src"; mkdir -p "$src"; echo x > "$src/f"
hash=$(_tree_hash "$src"); echo "decal-ply-1.0-$hash.noarch.rpm" > "$STUBS/want"
out=$(FILES_REPLACES="plymouth-theme-angular" files_install ply "$src" /usr/share/plymouth/themes/angular 2>&1)
assert_not_contains "$out" "noise" "the container build is quiet when it works"
assert_contains "$(calls)" "podman run" "rpm built in container"
assert_contains "$(calls)" "rpm-ostree install --uninstall=plymouth-theme-angular $T_TMP/rpms/decal-ply-1.0-$hash.noarch.rpm" "single transaction swap"
assert_file "$LS_RUNTMP/reboot" "reboot flagged"
assert_eq "$(cat "$DECAL_STATE/files/ply.rpm")" "decal-ply" "state records rpm name"
# declared dependencies go into the RPM (rpm-ostree then keeps them) and into its hash (so it's rebuilt)
stub podman 'for a; do case $a in *:/root/rpmbuild:Z) cp "${a%%:*}"/SPECS/*.spec "$STUBS/spec";; esac; done; mkdir -p "$DECAL_RPM_DIR"; touch "$DECAL_RPM_DIR/$(cat "$STUBS/want")"'
h2=$(printf '%s %s' "$hash" "plymouth-plugin-script" | sha256sum | cut -c1-12); echo "decal-req-1.0-$h2.noarch.rpm" > "$STUBS/want"
( FILES_REQUIRES="plymouth-plugin-script" files_install req "$src" /usr/share/plymouth/themes/x ) >/dev/null 2>&1
assert_contains "$(cat "$STUBS/spec" 2>/dev/null)" "Requires:  plymouth-plugin-script" "spec requires the plugin"
assert_contains "$(calls)" "decal-req-1.0-$h2.noarch.rpm" "requirements change the RPM hash"
# a failed build shows the build's own error
stub podman 'echo "error: Bad spec line 7"; exit 1'
out=$( (_rpm_build decal-bad 0000 "$src" /usr/share/x "$T_TMP/rpms-bad") 2>&1 ); assert_eq "$?" "1" "failed build rc"
assert_contains "$out" "Bad spec line 7" "failed build shows why"
n0=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -user "$(id -u)" -newer "$T_TMP" 2>/dev/null | wc -l)
( _rpm_build decal-bad 0000 "$src" /usr/share/x "$T_TMP/rpms-bad" ) >/dev/null 2>&1
stub podman 'exit 0'; ( _rpm_build decal-norpm 0000 "$src" /usr/share/x "$T_TMP/rpms-bad" ) >/dev/null 2>&1
stub podman 'echo "error: Bad spec line 7"; exit 1'
assert_eq "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tmp.*' -user "$(id -u)" -newer "$T_TMP" 2>/dev/null | wc -l)" "$n0" "failed builds leave no temp dir"
stub podman 'mkdir -p "$DECAL_RPM_DIR"; touch "$DECAL_RPM_DIR/$(cat "$STUBS/want")"'

# already layered with same hash -> no-op
cat > "$JSON" <<EOF
{"deployments":[{"booted":false,"osname":"default","checksum":"new","serial":0,
 "requested-local-packages":["decal-ply-1.0-$hash.noarch"],"regenerate-initramfs":true},
 {"booted":true,"osname":"default","checksum":"abc","serial":0}]}
EOF
: > "$STUBS/calls"; files_install ply "$src" /usr/share/plymouth/themes/angular
assert_not_contains "$(calls)" "rpm-ostree install" "idempotent"
files_installed ply; assert_eq "$?" "0" "installed via pending"

# files_remove uninstalls and clears state
: > "$STUBS/calls"; files_remove ply
assert_contains "$(calls)" "rpm-ostree uninstall decal-ply" "uninstall"
assert_nofile "$DECAL_STATE/files/ply.rpm" "state cleared"

# initramfs: enable on first marker, disable when last goes (regeneration was off before: seeded, as plymouth adoption does)
initramfs_seed_prior disabled
: > "$STUBS/calls"; initramfs_require ply
assert_contains "$(calls)" "rpm-ostree initramfs --enable" "enable"
: > "$STUBS/calls"; initramfs_release ply
assert_contains "$(calls)" "rpm-ostree initramfs --disable" "disable when last"
# dry-run fidelity: require must print "enable" even though the marker isn't written in dry-run,
# and the RPM build must not create directories
: > "$STUBS/calls"; rm -rf "$DECAL_STATE/initramfs" "$DECAL_RPM_DIR"
out=$(LS_DRY_RUN=1 initramfs_require ply 2>&1); assert_contains "$out" "rpm-ostree initramfs --enable" "dry-run require shows enable"
assert_contains "$(grep "rpm-ostree initramfs" <<<"$out" | tail -1)" "--enable" "dry-run require ends enabled"
src2="$T_TMP/src2"; mkdir -p "$src2"; echo y > "$src2/g"
LS_DRY_RUN=1 files_install dry "$src2" /usr/share/x 2>/dev/null; assert_nofile "$DECAL_RPM_DIR" "dry-run creates no rpm dir"
# user already had regeneration on with extra dracut args (e.g. TPM unlock): keep args, never disable on release
rm -rf "$DECAL_STATE/initramfs" "$DECAL_STATE/initramfs.prior"
cat > "$JSON" <<'EOF2'
{"deployments":[{"booted":true,"osname":"default","checksum":"abc","serial":0,
 "regenerate-initramfs":true,"initramfs-args":["--force-add","tpm2-tss"]}]}
EOF2
: > "$STUBS/calls"; initramfs_require tpmuser
assert_contains "$(calls)" "rpm-ostree initramfs --enable --arg=--force-add --arg=tpm2-tss" "require keeps existing dracut args"
: > "$STUBS/calls"; initramfs_release tpmuser
assert_not_contains "$(calls)" "--disable" "release never disables regeneration the user had on"
assert_contains "$(calls)" "rpm-ostree initramfs --enable --arg=--force-add --arg=tpm2-tss" "release regenerates with the user's args"
# already enabled with the same args: rebuild only when something changed that no staged deployment covered
: > "$STUBS/calls"; initramfs_require tpmuser; rm -f "$LS_RUNTMP/initramfs-dirty"; : > "$STUBS/calls"
initramfs_require tpmuser
assert_not_contains "$(calls)" "rpm-ostree initramfs" "nothing changed: no rebuild"
: > "$STUBS/calls"; initramfs_dirty; initramfs_require tpmuser
assert_contains "$(calls)" "rpm-ostree initramfs --enable --arg=--force-add --arg=tpm2-tss" "changed: rebuilt"
assert_nofile "$LS_RUNTMP/initramfs-dirty" "rebuild clears the change"
: > "$STUBS/calls"; initramfs_dirty; _pkg_add htop; initramfs_require tpmuser
assert_not_contains "$(calls)" "rpm-ostree initramfs" "a deployment staged after the change already rebuilt it"
initramfs_release tpmuser >/dev/null 2>&1
# atomic: base-image package -> override remove; layered -> uninstall; restore puts each back its own way
cat > "$JSON" <<'EOF2'
{"deployments":[{"booted":true,"osname":"default","checksum":"abc","serial":0,"requested-packages":["htop"]}]}
EOF2
stub rpm 'exit 0'; : > "$STUBS/calls"
pkg_uninstall tst firefox htop
assert_contains "$(calls)" "rpm-ostree override remove firefox" "base package hidden"
assert_contains "$(calls)" "rpm-ostree uninstall htop" "layered package uninstalled"
assert_eq "$(sort "$DECAL_STATE/pkgs/tst.removed" | tr '\n' ' ')" "base:firefox layer:htop " "recorded with origin"
: > "$STUBS/calls"; pkg_restore tst
assert_contains "$(calls)" "rpm-ostree override reset firefox" "base package back"
assert_contains "$(calls)" "rpm-ostree install --allow-inactive htop" "layered package back"
t_done
