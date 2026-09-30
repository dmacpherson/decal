#!/usr/bin/env bash
# pkg_uninstall refuses cascades and restores exactly, against the real package manager.
set -euo pipefail
export DECAL_ALLOW_ROOT=1 LS_RUNTMP=$(mktemp -d) LS_REPO=/repo
. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) apt-get update -qq; apt-get install -y -qq python3 hello >/dev/null; leaf=hello; needed=libc6 ;;
  *" arch "*) pacman -Sy --noconfirm --needed python which >/dev/null; leaf=which; needed=glibc ;;
  *) dnf -qy install python3 which >/dev/null; leaf=which; needed=glibc ;;
esac
source /repo/lib/common.sh; source /repo/lib/platform.sh; platform_load
if (pkg_uninstall e2e "$needed") 2>/dev/null; then echo "FAIL: removed $needed"; exit 1; fi
pkg_uninstall e2e "$leaf"; if _pkg_present "$leaf"; then echo "FAIL: $leaf still installed"; exit 1; fi
pkg_restore e2e; _pkg_present "$leaf" || { echo "FAIL: $leaf not restored"; exit 1; }
echo "PASS uninstall $ID"
