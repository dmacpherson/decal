# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
PKG_MAP[plymouth-script-plugin]=plymouth-plugin-script
_pkg_present() { rpm -q --quiet -- "$1"; }
_pkg_add() { srun dnf install -y -- "$@"; }
_pkg_rm() { srun dnf remove -y --setopt=clean_requirements_on_remove=False -- "$@"; }
_pkg_del() { srun dnf remove -y -- "$@"; }
_initramfs_rebuild() { srun dracut -f --regenerate-all; }

PKG_MAP[dnf-actions-plugin]=libdnf5-plugin-actions
# txn_hooks_add OWNER PRE POST : dnf5 actions plugin (dnf4 has no pre-transaction hook -> unsupported)
txn_hooks_add() {
  if [[ ${DECAL_NO_DNF5:-0} == 1 ]] || ! have dnf5; then warn "dnf5 not found: package-transaction hooks unsupported here"; return 1; fi
  pkg_install "$1" dnf-actions-plugin
  printf 'pre_transaction::::%s\npost_transaction::::%s\n' "$2" "$3" | etc_write "$1" "/etc/dnf/libdnf5-plugins/actions.d/decal-$1.actions"
}

_pkg_del_check() { local out; out=$(rpm -e --test -- "$@" 2>&1) || { echo "$out" | tr '\n' ' '; return 1; }; }
PKG_MAP[docker-engine]=moby-engine
