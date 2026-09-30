# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
PKG_MAP[plymouth-script-plugin]=""   # script plugin ships in the plymouth package
_pkg_present() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
_pkg_add() {
  if [[ ! -e ${LS_RUNTMP:-/nonexistent}/apt-updated ]]; then srun apt-get update; [[ -n ${LS_RUNTMP:-} ]] && : > "$LS_RUNTMP/apt-updated"; fi
  srun env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}
_pkg_rm() { srun env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"; }  # remove, not purge: config files stay
_pkg_del() { srun env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"; }  # purge: we only remove what we installed
_pkg_snapshot() { dpkg-query -W -f='${Package}\n' 2>/dev/null; }
_pkg_unneeded() { apt-get -s autoremove 2>/dev/null | awk '/^Remv /{print $2}'; }   # simulation only
_initramfs_rebuild() { srun update-initramfs -u -k all; }

txn_hooks_add() {
  printf 'DPkg::Pre-Invoke {"%s || true";};\nDPkg::Post-Invoke {"%s || true";};\n' "$2" "$3" | etc_write "$1" "/etc/apt/apt.conf.d/80decal-$1"
}

_pkg_del_check() {
  local want=" $* " extra="" p out
  # apt refuses impossible/essential removals by failing the simulation (exit 100): refuse too
  out=$(apt-get -s remove "$@" 2>&1) || { grep -vE '^(Reading|Building|Solving)' <<<"$out" | tr '\n' ' '; return 1; }
  # shellcheck disable=SC2013  # package names never contain spaces
  for p in $(awk '/^Remv /{print $2}' <<<"$out"); do [[ $want == *" $p "* ]] || extra+="$p "; done
  echo "${extra% }"
}
