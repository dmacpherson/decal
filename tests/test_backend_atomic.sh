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
stub rpm-ostree; stub podman 'mkdir -p "$DECAL_RPM_DIR"; touch "$DECAL_RPM_DIR/$(cat "$STUBS/want")"'
src="$T_TMP/src"; mkdir -p "$src"; echo x > "$src/f"
hash=$(_tree_hash "$src"); echo "decal-ply-1.0-$hash.noarch.rpm" > "$STUBS/want"
FILES_REPLACES="plymouth-theme-angular" files_install ply "$src" /usr/share/plymouth/themes/angular
assert_contains "$(calls)" "podman run" "rpm built in container"
assert_contains "$(calls)" "rpm-ostree install --uninstall=plymouth-theme-angular $T_TMP/rpms/decal-ply-1.0-$hash.noarch.rpm" "single transaction swap"
assert_file "$LS_RUNTMP/reboot" "reboot flagged"
assert_eq "$(cat "$DECAL_STATE/files/ply.rpm")" "decal-ply" "state records rpm name"

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
assert_not_contains "$out" "--disable" "dry-run require never disables"
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
