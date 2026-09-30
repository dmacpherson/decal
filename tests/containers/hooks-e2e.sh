#!/usr/bin/env bash
# Proves the package-manager hooks really run around a real transaction.
set -euo pipefail
export DECAL_ALLOW_ROOT=1 LS_RUNTMP=$(mktemp -d) LS_REPO=/repo
. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) apt-get update -qq; apt-get install -y -qq python3 >/dev/null; small=hello ;;
  *" arch "*) pacman -Sy --noconfirm --needed python >/dev/null; small=which ;;
  *) dnf -qy install python3 >/dev/null; small=which ;;
esac
source /repo/lib/common.sh; source /repo/lib/platform.sh; platform_load
printf '#!/bin/sh
echo "$1" >> /tmp/hook.log
' > /usr/local/bin/fake-helper; chmod +x /usr/local/bin/fake-helper
txn_hooks_add e2e "/usr/local/bin/fake-helper umount" "/usr/local/bin/fake-helper mount"
case $PLATFORM in debian) apt-get install -y -qq "$small" >/dev/null ;; arch) pacman -S --noconfirm "$small" >/dev/null ;; *) dnf -qy install "$small" >/dev/null ;; esac
got=$(tr '\n' ' ' < /tmp/hook.log)
[[ $got == "umount mount "* ]] || { echo "FAIL hooks: got [$got]"; exit 1; }
txn_hooks_remove e2e; : > /tmp/hook.log
case $PLATFORM in debian) apt-get install -y -qq --reinstall "$small" >/dev/null ;; arch) pacman -S --noconfirm "$small" >/dev/null ;; *) dnf -qy reinstall "$small" >/dev/null ;; esac
[[ ! -s /tmp/hook.log ]] || { echo "FAIL hooks still run after removal"; exit 1; }
echo "PASS hooks $ID"
