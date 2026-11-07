# shellcheck shell=bash disable=SC2034,SC2154  # sourced by module.sh
# NetBird: NetBird's repo, the client and its tray app (netbird-ui, started at login). Its package turns the service on;
# on Fedora Atomic that can't happen while layering, so decal does it after the reboot. Signing in is yours.
NB_YUM_FPR=AA9C09AA9DEA2F58112B40DFDFFEAB2FD267A61F   # NetBird's yum repo key (pkgs.netbird.io/yum)
NB_APT_FPR=EFE37DF047DF7CCDF1FC54FA83F79AD029778355   # NetBird's apt repo key (pkgs.netbird.io/debian)
NB_AUTO="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/netbird-ui.desktop"
NB_AUTO_REC="$LS_USER_STATE/vpn.netbird-autostart"

_nb_on() { systemctl is-enabled --quiet netbird 2>/dev/null; }
netbird_add() {
  if [[ $PLATFORM == arch ]]; then warn "NetBird isn't in Arch's own repositories (only the AUR): skipped"; return 0; fi
  _mark netbird
  if ! _pkg_present netbird || ! _pkg_present netbird-ui; then
    if [[ $PLATFORM == debian ]]; then
      repo_add netbird --key https://pkgs.netbird.io/debian/public.key "$NB_APT_FPR" \
        --apt "deb [signed-by=KEYRING] https://pkgs.netbird.io/debian stable main"
    else
      repo_add netbird --key https://pkgs.netbird.io/yum/repodata/repomd.xml.key "$NB_YUM_FPR" \
        --dnf https://pkgs.netbird.io/yum/ --repo-gpgcheck
    fi
    pkg_install vpn-netbird netbird netbird-ui
  fi
  if ! have netbird; then
    warn "NetBird is installed for after the reboot: then run decal add vpn again to turn it on"; return 0
  fi
  if ! _nb_on; then
    step "turning on the NetBird service"
    state_append "$ST/enabled" netbird.service
    srun netbird service install; srun netbird service start
  fi
  if [[ ! -e $NB_AUTO ]]; then
    if [[ $LS_DRY_RUN == 1 ]]; then log "[dry-run] write $NB_AUTO"
    else
      mkdir -p "$(dirname "$NB_AUTO")" "$LS_USER_STATE"; : > "$NB_AUTO_REC"
      printf '[Desktop Entry]\nType=Application\nName=NetBird\nExec=netbird-ui\nIcon=netbird\nX-GNOME-Autostart-enabled=true\n' > "$NB_AUTO"
    fi
  fi
  info "NetBird is ready: sign in from the NetBird icon in the tray (from your next login; or run netbird up)"
}
netbird_remove() {
  if [[ -e $NB_AUTO_REC ]]; then run rm -f "$NB_AUTO" "$NB_AUTO_REC"; fi
  if rec_has "$ST/enabled" netbird.service; then
    if have netbird; then srun netbird service stop || true; srun netbird service uninstall || true; fi
    state_drop "$ST/enabled" netbird.service
  fi
  pkg_remove vpn-netbird
  repo_remove netbird
  info "this machine is still listed in your NetBird dashboard: remove it there if you're done with it"
}
netbird_status() {
  if [[ $PLATFORM == arch ]]; then echo "skipped: not available on Arch"; return 0; fi
  if ! _pkg_present netbird || ! _pkg_present netbird-ui; then echo "not installed"; return 0; fi
  if ! have netbird; then echo "reboot pending"; return 0; fi
  if ! _nb_on; then echo "service off"; return 0; fi
  if [[ ! -e $NB_AUTO ]]; then echo "tray app not started at login"; fi
}
netbird_stamp() { _nb_on; }
