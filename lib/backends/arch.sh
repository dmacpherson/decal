# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
PKG_MAP[plymouth-script-plugin]=""   # all plymouth plugins ship in the plymouth package
_pkg_present() { pacman -Q "$1" >/dev/null 2>&1; }
_pkg_add() { srun pacman -S --needed --noconfirm "$@"; }
_pkg_rm() { srun pacman -R --noconfirm "$@"; }
_pkg_del() { srun pacman -Rs --noconfirm "$@"; }
_initramfs_rebuild() { srun mkinitcpio -P; }

txn_hooks_add() {
  _pacman_hook PreTransaction "$2" | etc_write "$1" "/etc/pacman.d/hooks/80-decal-$1-pre.hook"
  _pacman_hook PostTransaction "$3" | etc_write "$1" "/etc/pacman.d/hooks/80-decal-$1-post.hook"
}

_pkg_del_check() { local out; out=$(pacman -Rp "$@" 2>&1 >/dev/null) || { echo "$out" | tr '\n' ' '; return 1; }; }
PKG_MAP[docker-engine]=docker
