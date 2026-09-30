#!/usr/bin/env bash
set -euo pipefail
export DECAL_ALLOW_ROOT=1 DECAL_SKIP_INITRAMFS=1
. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) apt-get update -qq; apt-get install -y -qq python3 git ca-certificates >/dev/null; pkgs() { dpkg-query -W -f='${Package}\n' | sort; } ;;
  *" arch "*) pacman -Sy --noconfirm --needed python git >/dev/null; pkgs() { pacman -Qq | sort; } ;;
  *) dnf -qy install python3 git >/dev/null; pkgs() { rpm -qa --qf '%{NAME}\n' | sort; } ;;
esac
export DECAL_PROFILE=/repo/examples/profile
conf_state() { [[ -e /etc/plymouth/plymouthd.conf ]] && sha256sum /etc/plymouth/plymouthd.conf || echo absent; }
before_pkgs=$(pkgs); before_conf=$(conf_state)
/repo/decal add plymouth
st=$(/repo/decal status plymouth | awk '{$1=""; sub(/^ +/,""); print}'); echo "status after add: $st"; [[ $st == installed* ]] || { echo "FAIL status after add"; exit 1; }
[[ -f /usr/share/plymouth/themes/angular/angular.plymouth ]] || { echo "FAIL theme files"; exit 1; }
if command -v plymouth-set-default-theme >/dev/null; then echo "default theme: $(plymouth-set-default-theme)"; [[ $(plymouth-set-default-theme) == angular ]] || { echo "FAIL default theme"; exit 1; }; fi
/repo/decal add plymouth   # idempotent
/repo/decal remove plymouth
st=$(/repo/decal status plymouth | awk '{$1=""; sub(/^ +/,""); print}'); echo "status after remove: $st"; [[ $st == not-installed* ]] || { echo "FAIL status after remove: $st"; exit 1; }
[[ $(conf_state) == "$before_conf" ]] || { echo "FAIL conf not restored"; exit 1; }
missing=$(comm -23 <(echo "$before_pkgs") <(pkgs)); [[ -z $missing ]] || { echo "FAIL removed pre-existing packages: $missing"; exit 1; }
[[ ! -e /usr/share/plymouth/themes/angular ]] || { echo "FAIL theme dir left"; exit 1; }
echo "PASS $ID"
