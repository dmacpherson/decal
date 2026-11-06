#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
t_setup; fixture_profile
unset DISPLAY WAYLAND_DISPLAY
stub id 'case "$1" in -un) echo tester;; *) /usr/bin/id "$@";; esac'
# a fake package database shared by the fake package managers: install adds names, remove takes them out
export PKGDB="$T_TMP/pkgdb"; : > "$PKGDB"
_db='for a in "$@"; do case $a in -*|install|remove|purge|update|uninstall|env|DEBIAN_FRONTEND=*) ;; *) if [[ $op == add ]]; then echo "$a" >> "$PKGDB"; else sed -i "/^$a\$/d" "$PKGDB"; fi;; esac; done'
stub rpm 'grep -qxF -- "${*: -1}" "$PKGDB"'
stub dnf 'op=""; case $1 in install) op=add;; remove) op=del;; esac; [[ -z $op ]] || { '"$_db"'; }; true'
stub rpm-ostree 'op=""; case $1 in install) op=add;; uninstall) op=del;; esac; [[ -z $op ]] || { '"$_db"'; }; true'
stub apt-get 'op=""; case $1 in install) op=add;; remove|purge) op=del;; esac; [[ -z $op ]] || { '"$_db"'; }; true'
stub dpkg-query 'case "$*" in *Package*) cat "$PKGDB";; *) grep -qxF -- "${*: -1}" "$PKGDB" && echo "install ok installed";; esac'
stub pacman 'case $1 in -Q) grep -qxF -- "${*: -1}" "$PKGDB";; -S) op=add; '"$_db"';; -Rs|-R) op=del; '"$_db"';; esac'
stub systemctl 'case "$*" in *is-enabled*) exit 1;; esac; exit 0'
stub gsettings "echo \"['appindicatorsupport@rgcjonas.gmail.com']\""; stub gnome-shell 'echo "GNOME Shell 49.0"'
# this machine's own commands never count: only stubbed ones are "there" (the host may well have tailscale, GNOME)
base_pre() { _pending_root() { :; }; _initramfs_enabled() { return 1; }
  have() { case $1 in tailscale|netbird|wg|gnome-shell|gsettings) [[ -x $STUBS/$1 ]];; *) command -v "$1" >/dev/null 2>&1;; esac; }; }
fake_fetch() { :; }   # later blocks fake the vendors' keys
mod_run_pre() { base_pre; fake_fetch; }
run_mod() { mod_run vpn "module_$1"; }
# prof 'line;line' : the profile's [vpn] section (and its tag tables) replaced by these lines
prof() { python3 - "$PROFILE_DIR/profile.toml" "$1" <<'EOP'
import re,sys; p=sys.argv[1]; s=open(p).read(); s=re.sub(r"(?ms)^\[vpn(\.[^\]]*)?\]\n.*?(?=^\[|\Z)","",s); open(p,"w").write(s.rstrip("\n")+"\n\n[vpn]\n"+sys.argv[2].replace(";","\n")+"\n")
EOP
}
dnf_line() { grep "^dnf ${1:-}" "$STUBS/calls"; }

# --- NetworkManager-based: packages only, mapped per distro
export DECAL_PLATFORM=fedora
prof 'install = ["wireguard", "openvpn", "openconnect"]'
out=$(run_mod add 2>&1); assert_eq "$?" "0" "nm: add rc"
assert_contains "$(calls)" "dnf install -y -- wireguard-tools" "nm: wireguard-tools"
assert_contains "$(calls)" "dnf install -y -- NetworkManager-openvpn-gnome" "nm: the OpenVPN plugin (Fedora's name)"
assert_contains "$(calls)" "dnf install -y -- NetworkManager-openconnect-gnome" "nm: the OpenConnect plugin"
assert_contains "$out" "Settings → Network → VPN" "nm: says where connections are added"
assert_eq "$(run_mod status 2>/dev/null)" "installed (wireguard, openvpn, openconnect)" "nm: status"
# taken off the list: only that one goes
prof 'install = ["wireguard", "openconnect"]'; : > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_eq "$(dnf_line remove)" "dnf remove -y -- NetworkManager-openvpn-gnome" "nm: dropped from the list: only it removed"
run_mod remove >/dev/null 2>&1
assert_eq "$(cat "$PKGDB")" "" "nm: remove takes away what decal installed"
# already there (Fedora ships some plugins): used, not decal's, so never removed
echo NetworkManager-openvpn-gnome > "$PKGDB"; prof 'install = ["openvpn"]'; : > "$STUBS/calls"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_eq "$(dnf_line)" "" "nm: an existing plugin is neither installed nor removed"
assert_eq "$(cat "$PKGDB")" "NetworkManager-openvpn-gnome" "nm: and it's still there"
: > "$PKGDB"
# Debian and Arch package names
export DECAL_PLATFORM=debian; prof 'install = ["openvpn", "openconnect"]'; : > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "network-manager-openvpn-gnome" "debian: OpenVPN plugin name"
assert_contains "$(calls)" "network-manager-openconnect-gnome" "debian: OpenConnect plugin name"
run_mod remove >/dev/null 2>&1
export DECAL_PLATFORM=arch; : > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "pacman -S --needed --noconfirm -- networkmanager-openvpn" "arch: OpenVPN plugin name"
run_mod remove >/dev/null 2>&1; export DECAL_PLATFORM=fedora
# remove --only TAG: just what the tag added
prof 'install = ["wireguard"];[vpn.work];install = ["openconnect"]'
DECAL_TAGS=work run_mod add >/dev/null 2>&1; : > "$STUBS/calls"
DECAL_DROP=work run_mod drop >/dev/null 2>&1
assert_eq "$(dnf_line remove)" "dnf remove -y -- NetworkManager-openconnect-gnome" "drop: only the tag's service removed"
run_mod remove >/dev/null 2>&1
# untrusted profiles: an unknown name, or a repo of its own, never reach the module
prof 'install = ["evilvpn"]'; out=$(run_mod add 2>&1); rc=$?
assert_eq "$(( rc != 0 ))" "1" "an unknown name: refused"; assert_contains "$out" "expected one of" "an unknown name: says what's allowed"
prof 'install = ["wireguard"];repo = "https://evil.example/repo"'; run_mod add >/dev/null 2>&1; rc=$?
assert_eq "$(( rc != 0 ))" "1" "a repo setting: refused (unknown key)"
# dry run: nothing installed, nothing recorded
prof 'install = ["wireguard"]'; : > "$STUBS/calls"
( export LS_DRY_RUN=1; run_mod add ) >/dev/null 2>&1
assert_eq "$(dnf_line)" "" "dry run: nothing installed"; assert_nofile "$DECAL_STATE/vpn/services" "dry run: nothing recorded"
t_done
