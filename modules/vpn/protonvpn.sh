# shellcheck shell=bash disable=SC2034,SC2154  # sourced by module.sh
# Proton VPN: Proton's own repo and app (proton-vpn-gnome-desktop; its tray icon comes with it). Proton's Flatpak is
# community-made, so it isn't used. Signing in is yours, in the app.
PV_APT_FPR=84B0D3492C76C9C6F5873C18EDA3E22630349F1C   # Proton's apt repo key (repo.protonvpn.com/debian)
# Proton signs each Fedora release's repo with its own key, published ahead of the release. Add the next one here when
# it appears (https://repo.protonvpn.com/fedora-N-stable/public_key.asc, its fingerprint checked against Proton's).
declare -gA PV_FEDORA_FPR=(
  [43]=7BB2808996C47DC9EECDA475F7EB64B08C03490D
  [44]=6929133BDE1CE1CFA9EDB286D84176F6844830D4
  [45]=D3AA11B3B1BFB96DF3CA26A2D59CE240EB3EE0B0
)
PV_PKG=proton-vpn-gnome-desktop

_pv_release() { local v; v=$(_os_release VERSION_ID); if [[ $v =~ ^[0-9]+$ && -n ${PV_FEDORA_FPR[$v]:-} ]]; then echo "$v"; fi; }
protonvpn_add() {
  if [[ $PLATFORM == arch ]]; then warn "Proton VPN isn't in Arch's own repositories (only the AUR): skipped"; return 0; fi
  if ! _pkg_present "$PV_PKG"; then
    if [[ $PLATFORM == debian ]]; then
      _mark protonvpn
      repo_add protonvpn-stable --key https://repo.protonvpn.com/debian/public_key.asc "$PV_APT_FPR" \
        --apt "deb [signed-by=KEYRING] https://repo.protonvpn.com/debian stable main"
    else
      local v r keys=(); v=$(_pv_release)
      if [[ -z $v ]]; then
        warn "Proton VPN: this decal doesn't know Proton's signing key for Fedora $(_os_release VERSION_ID) (it knows $(printf '%s\n' "${!PV_FEDORA_FPR[@]}" | sort -n | paste -sd' ')): skipped; a newer decal will"
        return 0
      fi
      _mark protonvpn
      for r in $(printf '%s\n' "${!PV_FEDORA_FPR[@]}" | sort -n); do
        if (( r >= v )); then keys+=(--key "https://repo.protonvpn.com/fedora-$r-stable/public_key.asc" "${PV_FEDORA_FPR[$r]}"); fi
      done
      # shellcheck disable=SC2016  # dnf fills in $releasever
      repo_add protonvpn-stable "${keys[@]}" --dnf 'https://repo.protonvpn.com/fedora-$releasever-stable'
    fi
    if [[ $PLATFORM == fedora-atomic ]]; then
      warn "Proton supports Fedora Workstation; on Fedora Atomic its app is layered, which Proton doesn't officially support"
    fi
    pkg_install vpn-protonvpn "$PV_PKG"
  else
    _mark protonvpn
  fi
  info "Proton VPN is ready: open it from your apps and sign in"
}
protonvpn_remove() { pkg_remove vpn-protonvpn; repo_remove protonvpn-stable; }
protonvpn_status() {
  if [[ $PLATFORM == arch ]]; then echo "skipped: not available on Arch"; return 0; fi
  if ! _pkg_present "$PV_PKG"; then
    if [[ $PLATFORM != debian && -z $(_pv_release) ]]; then echo "skipped: no Proton key for this Fedora release yet"; else echo "not installed"; fi
  fi
}
protonvpn_stamp() { _pkg_present "$PV_PKG"; }
