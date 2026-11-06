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

# --- NetBird
NBY=AA9C09AA9DEA2F58112B40DFDFFEAB2FD267A61F; NBA=EFE37DF047DF7CCDF1FC54FA83F79AD029778355
fake_key "$K/nb-yum.asc" "$NBY"; fake_key "$K/nb-apt.asc" "$NBA"
fake_fetch() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"
  case $1 in https://pkgs.netbird.io/yum/repodata/repomd.xml.key) echo "$K/nb-yum.asc";; https://pkgs.netbird.io/debian/public.key) echo "$K/nb-apt.asc";; *) return 1;; esac; }; }
AUTO="$XDG_CONFIG_HOME/autostart/netbird-ui.desktop"
reset_nb() { rm -rf "$DECAL_STATE" "$DECAL_USER_STATE" "$DECAL_ROOT/etc" "$AUTO" "$STUBS/netbird"; : > "$PKGDB"; : > "$STUBS/calls"; }
prof 'install = ["netbird"]'
# Fedora: NetBird's repo and both packages; its package turns the service on itself; the UI at login
reset_nb; export DECAL_PLATFORM=fedora; stub netbird
stub systemctl 'case "$*" in *"is-enabled --quiet netbird"*) exit 0;; *is-enabled*) exit 1;; esac; exit 0'
out=$(run_mod add 2>&1); assert_eq "$?" "0" "netbird: rc"
assert_contains "$(cat "$DECAL_ROOT/etc/yum.repos.d/netbird.repo")" "baseurl=https://pkgs.netbird.io/yum/" "netbird: NetBird's repo"
assert_contains "$(calls)" "dnf install -y -- netbird netbird-ui" "netbird: both packages"
assert_not_contains "$(calls)" "netbird service install" "netbird: the package already turned its service on"
assert_contains "$(cat "$AUTO")" "Exec=netbird-ui" "netbird: the tray app at login"
assert_contains "$out" "sign in from the NetBird icon" "netbird: says what to do next"
: > "$STUBS/calls"; out=$(run_mod remove 2>&1)
assert_contains "$(calls)" "dnf remove -y -- netbird netbird-ui" "netbird: remove: packages"
assert_nofile "$AUTO" "netbird: remove: login entry"
assert_nofile "$DECAL_ROOT/etc/yum.repos.d/netbird.repo" "netbird: remove: repo"
assert_contains "$out" "NetBird dashboard" "netbird: remove: says the machine is still listed there"
# Fedora Atomic after the reboot: the service isn't on yet (the package couldn't do it while layering): decal does it
reset_nb; export DECAL_PLATFORM=fedora-atomic; printf 'netbird\nnetbird-ui\n' > "$PKGDB"; stub netbird
stub systemctl 'case "$*" in *is-enabled*) exit 1;; esac; exit 0'
run_mod add >/dev/null 2>&1
assert_contains "$(calls)" "netbird service install" "atomic: decal installs the service"
assert_contains "$(calls)" "netbird service start" "atomic: and starts it"
: > "$STUBS/calls"; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "netbird service uninstall" "atomic: remove takes the service away"
# your own login entry stays
reset_nb; export DECAL_PLATFORM=fedora; stub netbird; mkdir -p "$(dirname "$AUTO")"; echo mine > "$AUTO"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_eq "$(cat "$AUTO")" "mine" "netbird: your own login entry is never removed"
# Debian: NetBird's apt repo and key
reset_nb; export DECAL_PLATFORM=debian; stub netbird; run_mod add >/dev/null 2>&1
assert_eq "$(cat "$DECAL_ROOT/etc/apt/sources.list.d/netbird.list")" "deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.asc] https://pkgs.netbird.io/debian stable main" "debian: NetBird's repo"
run_mod remove >/dev/null 2>&1
# Arch: only in the AUR: skipped with a word, the rest of the run goes on
reset_nb; export DECAL_PLATFORM=arch; prof 'install = ["netbird", "wireguard"]'
out=$(run_mod add 2>&1); assert_eq "$?" "0" "arch: rc"
assert_contains "$out" "only the AUR" "arch: says why NetBird is skipped"
assert_contains "$(calls)" "wireguard-tools" "arch: the rest installed"
assert_eq "$(run_mod status 2>/dev/null)" "installed (netbird: not available on Arch, wireguard)" "arch: status counts the skip as done"
run_mod remove >/dev/null 2>&1
stub systemctl 'case "$*" in *is-enabled*) exit 1;; esac; exit 0'

# --- Proton VPN
PA=84B0D3492C76C9C6F5873C18EDA3E22630349F1C; P44=6929133BDE1CE1CFA9EDB286D84176F6844830D4; P45=D3AA11B3B1BFB96DF3CA26A2D59CE240EB3EE0B0
fake_key "$K/pv-apt.asc" "$PA"; fake_key "$K/pv-44.asc" "$P44"; fake_key "$K/pv-45.asc" "$P45"
fake_fetch() { ls_fetch() { echo "ls_fetch $*" >> "$STUBS/calls"
  case $1 in https://repo.protonvpn.com/debian/public_key.asc) echo "$K/pv-apt.asc";;
    https://repo.protonvpn.com/fedora-44-stable/public_key.asc) echo "$K/pv-44.asc";;
    https://repo.protonvpn.com/fedora-45-stable/public_key.asc) echo "$K/pv-45.asc";; *) return 1;; esac; }; }
reset_pv() { rm -rf "$DECAL_STATE" "$DECAL_ROOT/etc"; : > "$PKGDB"; : > "$STUBS/calls"; mkdir -p "$DECAL_ROOT/etc"; }
prof 'install = ["protonvpn"]'
# Fedora 44: Proton's repo with this release's key and the next one's (a Fedora upgrade keeps working)
reset_pv; export DECAL_PLATFORM=fedora; printf 'ID=fedora\nVERSION_ID=44\n' > "$DECAL_ROOT/etc/os-release"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "proton: rc"
R="$(cat "$DECAL_ROOT/etc/yum.repos.d/protonvpn-stable.repo")"
assert_contains "$R" "baseurl=https://repo.protonvpn.com/fedora-\$releasever-stable" "proton: Proton's repo"
assert_contains "$R" "decal-protonvpn-stable-$P44.asc" "proton: this release's key"
assert_contains "$R" "decal-protonvpn-stable-$P45.asc" "proton: the next release's key too"
assert_not_contains "$(calls)" "fedora-43-stable" "proton: older releases' keys not trusted"
assert_contains "$(calls)" "dnf install -y -- proton-vpn-gnome-desktop" "proton: the app"
assert_contains "$out" "sign in" "proton: says what to do next"
: > "$STUBS/calls"; run_mod remove >/dev/null 2>&1
assert_contains "$(calls)" "dnf remove -y -- proton-vpn-gnome-desktop" "proton: remove: the app"
assert_nofile "$DECAL_ROOT/etc/yum.repos.d/protonvpn-stable.repo" "proton: remove: the repo"
# Fedora Atomic: layered, with a word that Proton supports Fedora Workstation
reset_pv; export DECAL_PLATFORM=fedora-atomic; printf 'ID=bazzite\nID_LIKE="fedora"\nVERSION_ID=44\n' > "$DECAL_ROOT/etc/os-release"
out=$(run_mod add 2>&1)
assert_contains "$(calls)" "rpm-ostree install --allow-inactive proton-vpn-gnome-desktop" "atomic: layered"
assert_contains "$out" "Proton supports Fedora Workstation" "atomic: says it isn't officially supported"
run_mod remove >/dev/null 2>&1
# a Fedora release this decal has no Proton key for: skipped with a word, nothing trusted
reset_pv; export DECAL_PLATFORM=fedora; printf 'ID=fedora\nVERSION_ID=99\n' > "$DECAL_ROOT/etc/os-release"
out=$(run_mod add 2>&1); assert_eq "$?" "0" "unknown release: rc 0"
assert_contains "$out" "Fedora 99" "unknown release: says which"
assert_nofile "$DECAL_ROOT/etc/yum.repos.d/protonvpn-stable.repo" "unknown release: no repo"
# Debian: Proton's apt repo; set up before by Proton's own package (.sources): used as is
reset_pv; export DECAL_PLATFORM=debian; printf 'ID=debian\nVERSION_CODENAME=trixie\n' > "$DECAL_ROOT/etc/os-release"
run_mod add >/dev/null 2>&1
assert_eq "$(cat "$DECAL_ROOT/etc/apt/sources.list.d/protonvpn-stable.list")" "deb [signed-by=/usr/share/keyrings/protonvpn-stable-archive-keyring.asc] https://repo.protonvpn.com/debian stable main" "debian: Proton's repo"
run_mod remove >/dev/null 2>&1
reset_pv; printf 'ID=debian\n' > "$DECAL_ROOT/etc/os-release"; mkdir -p "$DECAL_ROOT/etc/apt/sources.list.d"; echo proton > "$DECAL_ROOT/etc/apt/sources.list.d/protonvpn-stable.sources"
run_mod add >/dev/null 2>&1; run_mod remove >/dev/null 2>&1
assert_nofile "$DECAL_ROOT/etc/apt/sources.list.d/protonvpn-stable.list" "debian: no second source next to Proton's own"
assert_eq "$(cat "$DECAL_ROOT/etc/apt/sources.list.d/protonvpn-stable.sources")" "proton" "debian: Proton's own source kept"
# Arch: only in the AUR
reset_pv; export DECAL_PLATFORM=arch; out=$(run_mod add 2>&1)
assert_contains "$out" "only the AUR" "arch: Proton VPN skipped with a word"

# --- stamp: what this machine uses; Bazzite's Tailscale that was never turned on isn't "used"
reset_pv; export DECAL_PLATFORM=fedora; export STAMP_NOTES="$T_TMP/notes"; : > "$STAMP_NOTES"
printf 'tailscale\nNetworkManager-openvpn-gnome\nproton-vpn-gnome-desktop\n' > "$PKGDB"
stub wg; stub systemctl 'case "$*" in *"is-enabled --quiet tailscaled.service"*) exit 0;; *is-enabled*) exit 1;; esac; exit 0'
assert_eq "$(mod_run vpn module_stamp 2>/dev/null)" '[vpn]
install = ["tailscale", "protonvpn", "wireguard", "openvpn"]' "stamp: services in use"
assert_contains "$(cat "$STAMP_NOTES")" "sign in again" "stamp: note says sign-ins aren't copied"
stub systemctl 'case "$*" in *is-enabled*) exit 1;; esac; exit 0'
assert_not_contains "$(mod_run vpn module_stamp 2>/dev/null)" "tailscale" "stamp: Tailscale installed but off: not stamped"
rm -f "$STUBS/wg"; : > "$PKGDB"
assert_eq "$(mod_run vpn module_stamp 2>/dev/null)" "" "stamp: nothing in use: no section"
# GNOME without the AppIndicator extension: tray icons won't show: a word on how to fix it
reset_pv; echo tailscale > "$PKGDB"; prof 'install = ["tailscale"]'; fake_tailscale
stub gsettings "echo \"['other@x']\""
out=$(run_mod add 2>&1); assert_contains "$out" "appindicatorsupport@rgcjonas.gmail.com" "tray: says which extension to add"
prof 'install = ["wireguard"]'; out=$(run_mod add 2>&1)
assert_not_contains "$out" "appindicator" "tray: no word when nothing needs a tray"
stub gsettings "echo \"['appindicatorsupport@rgcjonas.gmail.com']\""
run_mod remove >/dev/null 2>&1
t_done
