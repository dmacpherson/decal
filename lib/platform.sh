# shellcheck shell=bash disable=SC2034,SC2154,SC1090,SC1091  # sourced: vars shared across lib/ and modules
# Pick and load the backend for this system.
platform_detect() {
  if [[ -n ${DECAL_PLATFORM:-} ]]; then echo "$DECAL_PLATFORM"; return; fi
  local osr; osr=$(sys_path /etc/os-release)
  [[ -r $osr ]] || { echo unsupported; return; }
  local ids; ids=" $(. "$osr"; echo "${ID:-} ${ID_LIKE:-}") "
  if [[ -e $(sys_path /run/ostree-booted) ]]; then
    [[ $ids == *" fedora "* ]] && echo fedora-atomic || echo unsupported; return
  fi
  case $ids in
    *" fedora "*|*" rhel "*|*" centos "*) echo fedora ;;
    *" debian "*|*" ubuntu "*)            echo debian ;;
    *" arch "*)                           echo arch ;;
    *)                                    echo unsupported ;;
  esac
}
platform_load() {
  PLATFORM=$(platform_detect)
  [[ $PLATFORM != unsupported ]] || die "unsupported platform (supported: Fedora Atomic, Fedora/RHEL, Debian/Ubuntu, Arch)"
  unset PKG_MAP; declare -gA PKG_MAP=()
  # shellcheck source=/dev/null
  source "$LS_REPO/lib/backends/_shared.sh"
  # shellcheck source=/dev/null
  source "$LS_REPO/lib/backends/$PLATFORM.sh"
}
