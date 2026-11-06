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

# --- Tailscale
TS=2596A99EAAB33821893C0A79458CA832957F5868
K="$T_TMP/keys"; mkdir -p "$K"; fake_key "$K/ts.asc" "$TS"; fake_key -b "$K/ts.bin" "$TS"; stub_gpg
fake_fetch() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"
  case $1 in https://pkgs.tailscale.com/stable/fedora/repo.gpg) echo "$K/ts.asc";; https://pkgs.tailscale.com/stable/*.noarmor.gpg) echo "$K/ts.bin";; *) return 1;; esac; }; }
TRAY="$XDG_CONFIG_HOME/systemd/user/tailscale-systray.service"
WANTS="$DECAL_ROOT/etc/systemd/system/multi-user.target.wants/tailscaled.service"
# a fake tailscale: remembers the operator it's given; configure writes the tray unit like the real one
fake_tailscale() { stub tailscale 'case $1 in
  debug) printf "{\"OperatorUser\": \"%s\"}\n" "$(cat "$STUBS/ts-operator" 2>/dev/null)";;
  set) printf "%s" "${2#--operator=}" > "$STUBS/ts-operator";;
  configure) mkdir -p "$XDG_CONFIG_HOME/systemd/user"; echo unit > "$XDG_CONFIG_HOME/systemd/user/tailscale-systray.service";;
esac'; }
reset_ts() { rm -rf "$DECAL_STATE" "$DECAL_USER_STATE" "$DECAL_ROOT/etc" "$DECAL_ROOT/usr" "$XDG_CONFIG_HOME/systemd" "$STUBS/ts-operator" "$STUBS/tailscale"; : > "$PKGDB"; : > "$STUBS/calls"; }

# Bazzite: Tailscale already there with its service off: turned on now, no repo, no package; you control it, tray at login
reset_ts; export DECAL_PLATFORM=fedora-atomic; echo tailscale > "$PKGDB"; fake_tailscale
mkdir -p "$DECAL_ROOT/usr/lib/systemd/system"; : > "$DECAL_ROOT/usr/lib/systemd/system/tailscaled.service"
prof 'install = ["tailscale"]'
out=$(run_mod add 2>&1); assert_eq "$?" "0" "bazzite: rc"
assert_not_contains "$(calls)" "ls_fetch" "bazzite: no repo (already installed)"
assert_not_contains "$(calls)" "rpm-ostree install" "bazzite: nothing layered"
assert_eq "$(readlink "$WANTS")" "/usr/lib/systemd/system/tailscaled.service" "bazzite: tailscaled enabled"
assert_contains "$(calls)" "systemctl start tailscaled.service" "bazzite: and started now (no reboot)"
assert_contains "$(calls)" "tailscale set --operator=tester" "bazzite: you control it without sudo"
assert_contains "$(calls)" "tailscale configure systray --enable-startup=systemd" "bazzite: tray unit written by Tailscale"
assert_contains "$(calls)" "systemctl --user enable tailscale-systray.service" "bazzite: tray starts at login"
assert_contains "$out" "sign in from the Tailscale icon" "bazzite: says what to do next"
assert_eq "$(run_mod status 2>/dev/null)" "installed (tailscale)" "bazzite: status"
: > "$STUBS/calls"; out=$(run_mod remove 2>&1)
assert_contains "$(calls)" "systemctl --user disable --now tailscale-systray.service" "remove: tray off"
assert_nofile "$TRAY" "remove: tray unit gone"
assert_contains "$(calls)" "tailscale set --operator=" "remove: operator cleared"
assert_nofile "$WANTS" "remove: service off again"
assert_not_contains "$(calls)" "rpm-ostree uninstall" "remove: Bazzite's own Tailscale kept"
assert_eq "$(cat "$PKGDB")" "tailscale" "remove: package still there"
assert_contains "$out" "Tailscale admin console" "remove: says the machine is still listed there"

# Fedora Atomic, not installed: Tailscale's repo, layered; finished after the reboot
reset_ts
out=$(run_mod add 2>&1); assert_eq "$?" "0" "atomic: rc"
assert_contains "$(cat "$DECAL_ROOT/etc/yum.repos.d/tailscale.repo")" "baseurl=https://pkgs.tailscale.com/stable/fedora/\$basearch" "atomic: Tailscale's repo"
assert_contains "$(cat "$DECAL_ROOT/etc/yum.repos.d/tailscale.repo")" "repo_gpgcheck=1" "atomic: signed metadata checked"
assert_contains "$(calls)" "rpm-ostree install --allow-inactive tailscale" "atomic: layered"
assert_file "$WANTS" "atomic: enabled for after the reboot"
assert_not_contains "$(calls)" "systemctl start tailscaled" "atomic: not started (it isn't there until the reboot)"
assert_not_contains "$(calls)" "tailscale set" "atomic: no operator yet"
assert_contains "$out" "after the reboot" "atomic: says to run decal again after the reboot"
assert_eq "$(run_mod status 2>/dev/null)" "partial (tailscale: reboot pending)" "atomic: status"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_not_contains "$(calls)" "rpm-ostree install" "atomic: run again before the reboot: not layered twice"
# after the reboot: the rest
fake_tailscale; mkdir -p "$DECAL_ROOT/usr/lib/systemd/system"; : > "$DECAL_ROOT/usr/lib/systemd/system/tailscaled.service"
: > "$STUBS/calls"; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "tailscale set --operator=tester" "atomic after the reboot: operator set"
assert_eq "$(run_mod status 2>/dev/null)" "installed (tailscale)" "atomic after the reboot: status"
: > "$STUBS/calls"; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "rpm-ostree uninstall tailscale" "atomic: remove takes away what decal layered"
assert_nofile "$DECAL_ROOT/etc/yum.repos.d/tailscale.repo" "atomic: and its repo"

# Ubuntu: Tailscale's apt repo for this release, its binary key where Tailscale's instructions put it
reset_ts; export DECAL_PLATFORM=debian; mkdir -p "$DECAL_ROOT/etc"
printf 'ID=ubuntu\nVERSION_CODENAME=noble\nUBUNTU_CODENAME=noble\n' > "$DECAL_ROOT/etc/os-release"
fake_tailscale; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "ls_fetch https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg" "ubuntu: the release's key"
assert_eq "$(cat "$DECAL_ROOT/etc/apt/sources.list.d/tailscale.list")" "deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main" "ubuntu: the release's repo"
run_mod remove >/dev/null 2>&1
# Debian
reset_ts; mkdir -p "$DECAL_ROOT/etc"; printf 'ID=debian\nVERSION_CODENAME=trixie\n' > "$DECAL_ROOT/etc/os-release"
fake_tailscale; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "ls_fetch https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg" "debian: the release's key"
run_mod remove >/dev/null 2>&1
# Arch: from Arch's own repositories
reset_ts; export DECAL_PLATFORM=arch; fake_tailscale; run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "pacman -S --needed --noconfirm -- tailscale" "arch: Arch's package"
assert_not_contains "$(calls)" "ls_fetch" "arch: no repo"
run_mod remove >/dev/null 2>&1

# your own tray unit: used, never removed; no user session (ssh): a warning, the run carries on
reset_ts; export DECAL_PLATFORM=fedora; echo tailscale > "$PKGDB"; fake_tailscale
mkdir -p "$(dirname "$TRAY")"; echo mine > "$TRAY"; mkdir -p "$DECAL_ROOT/usr/lib/systemd/system"; : > "$DECAL_ROOT/usr/lib/systemd/system/tailscaled.service"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_eq "$(cat "$TRAY")" "mine" "your own tray unit is never removed"
rm -f "$TRAY"; stub systemctl 'case "$*" in *is-enabled*) exit 1;; *--user*) exit 1;; esac; exit 0'
out=$(run_mod add 2>&1); assert_eq "$?" "0" "no user session: rc 0"
assert_contains "$out" "next login" "no user session: says the tray starts at the next login"
run_mod remove >/dev/null 2>&1
stub systemctl 'case "$*" in *is-enabled*) exit 1;; esac; exit 0'
# tailscaled already enabled before decal: not recorded, so remove leaves it on
reset_ts; echo tailscale > "$PKGDB"; fake_tailscale; mkdir -p "$(dirname "$WANTS")" "$DECAL_ROOT/usr/lib/systemd/system"
ln -s /usr/lib/systemd/system/tailscaled.service "$WANTS"; : > "$DECAL_ROOT/usr/lib/systemd/system/tailscaled.service"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_eq "$(readlink "$WANTS")" "/usr/lib/systemd/system/tailscaled.service" "a service you had on stays on"
t_done
