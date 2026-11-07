# shellcheck shell=bash disable=SC2034,SC2154  # sourced by module.sh
# WireGuard, OpenVPN, OpenConnect: NetworkManager makes the connections (Settings → Network → VPN); decal adds the
# tools and plugins. nm-openvpn / nm-openconnect map to each distro's package (PKG_MAP in lib/backends).
_nm_add() { _mark "$1"; pkg_install "vpn-$1" "$2"; info "$3"; }   # SERVICE PACKAGE MESSAGE
_nm_status() { if ! _pkg_present "$(_pkg_name "$1")"; then echo "not installed"; fi; }

wireguard_add() { _nm_add wireguard wireguard-tools "WireGuard: import a .conf in Settings → Network → VPN, or use wg-quick"; }
wireguard_remove() { pkg_remove vpn-wireguard; }
wireguard_status() { _nm_status wireguard-tools; }
wireguard_stamp() { have wg; }

openvpn_add() { _nm_add openvpn nm-openvpn "OpenVPN: import a .ovpn file in Settings → Network → VPN"; }
openvpn_remove() { pkg_remove vpn-openvpn; }
openvpn_status() { _nm_status nm-openvpn; }
openvpn_stamp() { _pkg_present "$(_pkg_name nm-openvpn)"; }

openconnect_add() { _nm_add openconnect nm-openconnect "OpenConnect (Cisco AnyConnect, GlobalProtect, Fortinet, Juniper): add it in Settings → Network → VPN"; }
openconnect_remove() { pkg_remove vpn-openconnect; }
openconnect_status() { _nm_status nm-openconnect; }
openconnect_stamp() { _pkg_present "$(_pkg_name nm-openconnect)"; }
