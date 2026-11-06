# shellcheck shell=bash disable=SC2034,SC2154  # sourced by module.sh
# Tailscale: the package (Tailscale's repo; Arch's own; already there on Bazzite), tailscaled on, you as its operator
# (you and the tray control it without sudo), the tray icon at login. Signing in is yours: from the tray, or tailscale up.
TS_FPR=2596A99EAAB33821893C0A79458CA832957F5868   # Tailscale's package signing key (pkgs.tailscale.com)
TS_TRAY="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/tailscale-systray.service"   # written by tailscale configure systray
TS_TRAY_REC="$LS_USER_STATE/vpn.tailscale-tray"

_ts_repo() {
  local u=https://pkgs.tailscale.com/stable d c id
  case $PLATFORM in
    debian)
      c=$(_os_release UBUNTU_CODENAME); d=ubuntu
      if [[ -z $c ]]; then c=$(_os_release VERSION_CODENAME); if [[ $(_os_release ID) == ubuntu ]]; then d=ubuntu; else d=debian; fi; fi
      repo_add tailscale --key "$u/$d/$c.noarmor.gpg" "$TS_FPR" --apt "deb [signed-by=KEYRING] $u/$d $c main" ;;
    fedora|fedora-atomic)
      id=$(_os_release ID); d=fedora
      case $id in rhel|centos|rocky|almalinux) d="rhel/$(_os_release VERSION_ID | cut -d. -f1)" ;; esac
      repo_add tailscale --key "$u/$d/repo.gpg" "$TS_FPR" --dnf "$u/$d/\$basearch" --repo-gpgcheck ;;
  esac
}
_ts_operator() { tailscale debug prefs 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("OperatorUser", ""))' 2>/dev/null; }
_ts_tray_on() {
  [[ -e $TS_TRAY ]] && return 0   # yours, or already decal's
  if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] tailscale configure systray --enable-startup=systemd; systemctl --user enable --now tailscale-systray.service"; return 0; fi
  mkdir -p "$LS_USER_STATE"; : > "$TS_TRAY_REC"
  tailscale configure systray --enable-startup=systemd >/dev/null
  if systemctl --user daemon-reload 2>/dev/null && systemctl --user enable tailscale-systray.service 2>/dev/null; then
    systemctl --user start tailscale-systray.service 2>/dev/null || true
  else
    warn "the Tailscale tray icon starts at your next login (no desktop session to start it in now)"
  fi
}
_ts_tray_off() {
  [[ -e $TS_TRAY_REC ]] || return 0
  run systemctl --user disable --now tailscale-systray.service 2>/dev/null || true
  run rm -f "$TS_TRAY" "$TS_TRAY_REC"; run systemctl --user daemon-reload 2>/dev/null || true
}

tailscale_add() {
  _mark tailscale
  if ! _pkg_present tailscale; then _ts_repo; pkg_install vpn-tailscale tailscale; fi
  _svc_on tailscaled.service
  if ! have tailscale; then
    warn "Tailscale is installed for after the reboot: then run decal add vpn again to finish (control without sudo, tray icon)"
    return 0
  fi
  local me; me=$(id -un)
  if [[ $(_ts_operator) != "$me" ]]; then
    printf '%s\n' "$me" | swrite "$ST/tailscale.operator"
    srun tailscale set --operator="$me"
  fi
  _ts_tray_on
  info "Tailscale is ready: sign in from the Tailscale icon in the tray (or run tailscale up)"
}
tailscale_remove() {
  _ts_tray_off
  if [[ -r $ST/tailscale.operator ]]; then
    if have tailscale && [[ $(_ts_operator) == "$(cat "$ST/tailscale.operator")" ]]; then srun tailscale set --operator= || true; fi
    srun rm -f "$ST/tailscale.operator"
  fi
  _svc_off tailscaled.service
  pkg_remove vpn-tailscale
  repo_remove tailscale
  info "this machine is still listed in your Tailscale admin console: remove it there if you're done with it"
}
tailscale_status() {
  if ! _pkg_present tailscale; then echo "not installed"; return 0; fi
  if ! have tailscale; then echo "reboot pending"; return 0; fi
  if ! _svc_enabled tailscaled.service; then echo "service off"; return 0; fi
  if [[ $(_ts_operator) != "$(id -un)" ]]; then echo "needs sudo to control"; return 0; fi
  if [[ ! -e $TS_TRAY ]]; then echo "no tray icon"; fi
}
tailscale_stamp() { systemctl is-enabled --quiet tailscaled.service 2>/dev/null; }
